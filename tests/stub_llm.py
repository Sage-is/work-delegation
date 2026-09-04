#!/usr/bin/env python3
"""Scripted stand-in for an OpenAI-compatible /chat/completions endpoint.

Usage: stub_llm.py <port> <script.json> <record.jsonl>

script.json is a list of steps, one per request in order (the last step repeats).
Each step is one of:
  {"tool": "<name>", "args": {...}}          -> a tool_call response
  {"tools": [[name, args], ...]}             -> several tool_calls in one turn
  {"text": "..."}                            -> a plain assistant message
  {"status": 429, "error": "..."}            -> an HTTP error with a JSON error body
Any step may add "delay": <seconds>.
POST /reset re-reads the script and restarts the count. Every request is appended
to record.jsonl as {"n": i, "auth": ..., "body": ...}.
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, SCRIPT, RECORD = int(sys.argv[1]), sys.argv[2], sys.argv[3]
STATE = {"n": 0, "steps": []}


def load():
    with open(SCRIPT, encoding="utf-8") as fh:
        STATE["steps"] = json.load(fh)
    STATE["n"] = 0


def completion(step, n):
    msg = {"role": "assistant", "content": step.get("text")}
    calls = []
    if "tool" in step:
        calls = [(step["tool"], step.get("args", {}))]
    elif "tools" in step:
        calls = [tuple(c) for c in step["tools"]]
    if calls:
        msg["tool_calls"] = [
            {"id": f"call_{n}_{i}", "type": "function",
             "function": {"name": name, "arguments": json.dumps(args)}}
            for i, (name, args) in enumerate(calls)]
    return {"id": f"stub-{n}", "object": "chat.completion",
            "choices": [{"index": 0, "message": msg, "finish_reason": "tool_calls" if calls else "stop"}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 10, "cost": 0.0001}}


class H(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass  # the client gave up (timeout case); nothing to report

    def do_POST(self):
        if self.path.endswith("/reset"):
            load()
            return self._send(200, {"ok": True})
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        n = STATE["n"]
        STATE["n"] += 1
        with open(RECORD, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"n": n, "auth": self.headers.get("Authorization"),
                                 "body": body}) + "\n")
        steps = STATE["steps"]
        step = steps[min(n, len(steps) - 1)] if steps else {"text": "ok"}
        if step.get("delay"):
            time.sleep(step["delay"])
        if "status" in step:
            return self._send(step["status"], {"error": {"type": "stub", "message": step.get("error", "stub error")}})
        return self._send(200, completion(step, n))


load()
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
