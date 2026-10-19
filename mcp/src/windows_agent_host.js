#!/usr/bin/env node
// Persistent Windows owner of the agent relay's MCP stdio connection.
// The existing Windows startup relay supervises this process. Local agents
// use the loopback-only JSON API; the phone uses the authenticated WebSocket.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { readFile } from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const configPath = process.env.DEVOTA_AGENT_CONFIG;
if (!configPath) throw new Error("DEVOTA_AGENT_CONFIG must name the private relay configuration");
const config = JSON.parse(await readFile(configPath, "utf8"));
if (!config.pairToken || !config.repoRoot || !config.wsHost) {
  throw new Error("Relay configuration needs pairToken, repoRoot and wsHost");
}
const controlPort = config.controlPort ?? 18783;
const client = new Client({ name: "devota-windows-agent-host", version: "1.0.0" });
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(path.dirname(fileURLToPath(import.meta.url)), "server.js")],
  env: {
    ...process.env,
    DEVOTA_PAIR_TOKEN: config.pairToken,
    DEVOTA_REPO_ROOT: config.repoRoot,
    DEVOTA_BUILD_SERVER_URL: config.buildServerUrl,
    DEVOTA_WS_HOST: config.wsHost,
    DEVOTA_WS_PORT: String(config.wsPort ?? 8083),
    DEVOTA_ENABLE_WHOLE_DEVICE: "1",
  },
  stderr: "inherit",
});
transport.onclose = () => process.exit(1);
await client.connect(transport);

const host = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  // Reject browser-originated requests to this local control endpoint.
  if (req.headers.origin || req.headers["sec-fetch-site"]) {
    res.writeHead(403).end(JSON.stringify({ error: "local clients only" }));
    return;
  }
  try {
    let result;
    if (req.method === "GET" && req.url === "/health") {
      result = { service: "devota-windows-agent-host", status: "ok", pid: process.pid, wsHost: config.wsHost, wsPort: config.wsPort ?? 8083 };
    } else if (req.method === "GET" && req.url === "/tools") {
      result = await client.listTools();
    } else if (req.method === "POST" && req.url === "/") {
      if (!req.headers["content-type"]?.startsWith("application/json")) {
        res.writeHead(415).end(JSON.stringify({ error: "application/json required" }));
        return;
      }
      let body = "";
      for await (const chunk of req) {
        body += chunk;
        if (body.length > 2 * 1024 * 1024) throw new Error("request too large");
      }
      const call = JSON.parse(body);
      if (typeof call.name !== "string") throw new Error("tool name required");
      result = await client.callTool({ name: call.name, arguments: call.arguments ?? {} }, undefined, { timeout: 120000 });
    } else {
      res.writeHead(404).end(JSON.stringify({ error: "not found" }));
      return;
    }
    res.end(JSON.stringify(result));
  } catch (error) {
    res.writeHead(500).end(JSON.stringify({ error: error.message }));
  }
});
host.on("error", async () => { await client.close(); process.exit(1); });
host.listen(controlPort, "127.0.0.1", () => console.error(`[devota_host] local control listening on 127.0.0.1:${controlPort}`));
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, async () => { host.close(); await client.close(); process.exit(0); });
}
