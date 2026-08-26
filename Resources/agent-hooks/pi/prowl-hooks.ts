// Prowl managed hook extension for Pi (docs-ai 064.010).
//
// Relays Pi's native lifecycle events to the Prowl app that launched this session through the
// bundled `prowl agents _hook` bridge, which validates the launch token, caller ancestry, and
// working directory. Observation only: nothing here changes what the agent does, every failure
// is swallowed, and nothing is written to the terminal.
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const RUNTIME = "pi";
// `agent_end` precedes `agent_settled`, Pi's documented idle point, and is not forwarded.
const FORWARDED_EVENTS = ["session_start", "agent_settled", "session_shutdown"];
const TOKEN_VARIABLE = "PROWL_AGENT_HOOK_TOKEN";
const CLI = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "prowl-cli", "prowl");

// A main session's file is `<bucket>/<timestamp>_<uuid>.jsonl`; an in-process sub-agent (Oh My
// Pi's `task` tool) runs under its own session id whose file is nested inside the parent's
// session directory and named after the agent (`PongResponder.jsonl`). Its lifecycle events must
// not rotate the pane's session, but an approval it asks for still blocks the user.
const MAIN_SESSION_FILE = /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z_[0-9a-f-]{36}\.jsonl$/i;
let mainSessionId: string | undefined;

function isSubAgentSession(ctx: any): boolean {
  const file = ctx?.sessionManager?.getSessionFile?.();
  if (typeof file !== "string" || file.length === 0) return false;
  const name = file.slice(file.lastIndexOf("/") + 1);
  return !MAIN_SESSION_FILE.test(name);
}

function relay(name: string, event: any, ctx: any): void {
  try {
    if (!process.env[TOKEN_VARIABLE]) return;
    let sessionId = ctx?.sessionManager?.getSessionId?.();
    if (typeof sessionId !== "string" || sessionId.length === 0) return;
    if (isSubAgentSession(ctx)) {
      if (name !== "tool_approval_requested" || !mainSessionId) return;
      sessionId = mainSessionId;
    } else if (name === "session_start" || name === "session_switch") {
      mainSessionId = sessionId;
    }
    const payload = {
      hook_event_name: name,
      session_id: sessionId,
      cwd: typeof ctx?.cwd === "string" ? ctx.cwd : process.cwd(),
      reason: typeof event?.reason === "string" ? event.reason : undefined,
    };
    const child = spawn(CLI, ["agents", "_hook", RUNTIME, name], {
      stdio: ["pipe", "ignore", "ignore"],
      env: process.env,
    });
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
  } catch {
    // fail-open: the runtime must never notice a hook problem
  }
}

export default function (pi: any): void {
  for (const name of FORWARDED_EVENTS) {
    try {
      pi.on(name, (event: any, ctx: any) => {
        relay(name, event, ctx);
      });
    } catch {
      // an unknown event name on a newer Pi is not an error worth surfacing
    }
  }
}
