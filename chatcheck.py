#!/usr/bin/env python3
"""Drive two chat sockets end to end, without a browser.

Signs in as two seeded accounts, mints a ClientId for each (ADR 18), opens both
sockets and checks that what one sends arrives at the other.

It talks to the Domain the way the browser does, at http://localhost:800N.

Usage:  python3 chatcheck.py [domain] [chat-id]
"""
import asyncio, json, sys, urllib.request

import websockets

# The host port of each Domain with chat (docker-compose.yml).
PORTS = {"103mail.com": 8001, "example.com": 8002}

DOMAIN = sys.argv[1] if len(sys.argv) > 1 else "example.com"
CHAT   = sys.argv[2] if len(sys.argv) > 2 else "2"
HOST   = f"localhost:{PORTS[DOMAIN]}"


def post(path, body, tok=None):
    head = {"Content-Type": "application/json"}
    if tok:
        head["Authorization"] = "Bearer " + tok
    req = urllib.request.Request(f"http://{HOST}{path}", json.dumps(body).encode(), head, method="POST")
    return json.load(urllib.request.urlopen(req))


async def expect(ws, kind, timeout=5):
    """Read until a frame of this type arrives. Frames interleave, so a bare
    recv() will often hand back somebody else's presence push instead."""
    while True:
        frame = json.loads(await asyncio.wait_for(ws.recv(), timeout))
        if frame.get("type") == kind:
            return frame


async def main():
    a, b = f"bob@{DOMAIN}", f"carol@{DOMAIN}"
    ta = post("/api/v1/auth/token", {"email": a, "password": "password"})["value"]
    tb = post("/api/v1/auth/token", {"email": b, "password": "password"})["value"]
    ca = post("/api/v1/chat/session", {}, ta)["clientId"]
    cb = post("/api/v1/chat/session", {}, tb)["clientId"]

    async with websockets.connect(f"ws://{HOST}/ws/{ca}") as wa, \
               websockets.connect(f"ws://{HOST}/ws/{cb}") as wb:
        for ws, who in ((wa, a), (wb, b)):
            await ws.send(json.dumps({"type": "hello"}))
            print(f"ready    {who} userId={(await expect(ws, 'ready'))['userId']}")

        await wa.send(json.dumps({"type": "typing", "chatId": CHAT, "on": True}))
        t = await expect(wb, "typing")
        print(f"typing   {b} sees userId={t['userId']} on chatId={t['chatId']}")

        await wa.send(json.dumps({"type": "message", "chatId": CHAT, "body": "socket check", "id": "c1"}))
        m = await expect(wb, "message")
        print(f"message  {b} sees {m['message']['body']!r} from {m['message']['senderEmail']}")
        print("\nOK. The chatId differs per side because each user reads their own projection (ADR 3).")

asyncio.run(main())
