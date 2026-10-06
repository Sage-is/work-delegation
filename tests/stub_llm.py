#!/usr/bin/env python3
"""Scripted stand-in for an OpenAI-compatible gateway: /chat/completions and /responses.

Usage: stub_llm.py <port> <script.json> <record.jsonl>

script.json is a list of steps, one per request in order (the last step repeats).
Each step is one of:
  {"tool": "<name>", "args": {...}}          -> a tool_call response
  {"tools": [[name, args], ...]}             -> several tool_calls in one turn
  {"text": "..."}                            -> a plain assistant message
  {"status": 429, "error": "..."}            -> an HTTP error with a JSON error body
Any step may add:
  "delay": <s>   wait before answering at all
  "drip": <s>    wait between streamed chunks (a slow model that is still writing)
  "stall": <s>   go silent after the first chunk (a gateway that has hung mid-answer)
  "json": true   answer one JSON body even when the request asked for a stream
  "cost": null   leave the gateway's cost out of the usage (chat only)
A request with "stream": true gets server-sent events in the shape of the path's
protocol. POST /reset re-reads the script and restarts the count. Every request is
appended to record.jsonl as {"n": i, "auth": ..., "path": ..., "headers": ..., "body": ...}.
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


def calls_of(step):
    if "tool" in step:
        return [(step["tool"], step.get("args", {}))]
    return [tuple(c) for c in step.get("tools", [])]


def chat_usage(step):
    usage = {"prompt_tokens": 100, "completion_tokens": 10, "cost": step.get("cost", 0.0001)}
    return {k: v for k, v in usage.items() if v is not None}


def chat_body(step, n):
    msg = {"role": "assistant", "content": step.get("text")}
    calls = calls_of(step)
    if calls:
        msg["tool_calls"] = [
            {"id": f"call_{n}_{i}", "type": "function",
             "function": {"name": name, "arguments": json.dumps(args)}}
            for i, (name, args) in enumerate(calls)]
    return {"id": f"stub-{n}", "object": "chat.completion",
            "choices": [{"index": 0, "message": msg, "finish_reason": "tool_calls" if calls else "stop"}],
            "usage": chat_usage(step)}


def chat_chunks(step, n):
    head = {"id": f"stub-{n}", "object": "chat.completion.chunk"}
    yield head | {"choices": [{"index": 0, "delta": {"role": "assistant"}}]}
    text = step.get("text") or ""
    for part in (text[: len(text) // 2], text[len(text) // 2:]):
        if part:
            yield head | {"choices": [{"index": 0, "delta": {"content": part}}]}
    for i, (name, args) in enumerate(calls_of(step)):
        yield head | {"choices": [{"index": 0, "delta": {"tool_calls": [
            {"index": i, "id": f"call_{n}_{i}", "type": "function",
             "function": {"name": name, "arguments": ""}}]}}]}
        raw = json.dumps(args)
        for frag in (raw[: len(raw) // 2], raw[len(raw) // 2:]):
            yield head | {"choices": [{"index": 0, "delta": {"tool_calls": [
                {"index": i, "function": {"arguments": frag}}]}}]}
    yield head | {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
    yield head | {"choices": [], "usage": chat_usage(step)}


def response_items(step, n):
    items = []
    if step.get("text"):
        items.append({"type": "message", "role": "assistant",
                      "content": [{"type": "output_text", "text": step["text"]}]})
    for i, (name, args) in enumerate(calls_of(step)):
        items.append({"type": "function_call", "call_id": f"call_{n}_{i}", "name": name,
                      "arguments": json.dumps(args)})
    return items


def responses_body(step, n):
    return {"id": f"resp-{n}", "object": "response", "status": "completed",
            "output": response_items(step, n), "usage": {"input_tokens": 100, "output_tokens": 10}}


def responses_events(step, n):
    yield {"type": "response.created", "response": {"id": f"resp-{n}", "status": "in_progress"}}
    for item in response_items(step, n):
        yield {"type": "response.output_item.added", "item": item | {"arguments": ""} if "call_id" in item else item}
        yield {"type": "response.output_item.done", "item": item}
    yield {"type": "response.completed", "response": responses_body(step, n) | {"output": []}}


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

    def _stream(self, step, chunks, named_events):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        try:
            for i, chunk in enumerate(chunks):
                if i == 1 and step.get("stall"):
                    time.sleep(step["stall"])
                elif i and step.get("drip"):
                    time.sleep(step["drip"])
                event = f"event: {chunk['type']}\n" if named_events else ""
                self.wfile.write(f"{event}data: {json.dumps(chunk)}\n\n".encode())
                self.wfile.flush()
            if not named_events:
                self.wfile.write(b"data: [DONE]\n\n")
        except BrokenPipeError:
            pass

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
                                 "path": self.path, "headers": dict(self.headers),
                                 "body": body}) + "\n")
        steps = STATE["steps"]
        step = steps[min(n, len(steps) - 1)] if steps else {"text": "ok"}
        if step.get("delay"):
            time.sleep(step["delay"])
        if "status" in step:
            return self._send(step["status"], {"error": {"type": "stub", "message": step.get("error", "stub error")}})
        responses = self.path.endswith("/responses")
        if not body.get("stream") or step.get("json"):
            if step.get("drip"):  # the same slow model, seen whole: all the chunks' time at once
                chunks = responses_events(step, n) if responses else chat_chunks(step, n)
                time.sleep(step["drip"] * (len(list(chunks)) - 1))
            return self._send(200, responses_body(step, n) if responses else chat_body(step, n))
        if responses:
            return self._stream(step, list(responses_events(step, n)), named_events=True)
        return self._stream(step, list(chat_chunks(step, n)), named_events=False)


load()
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
