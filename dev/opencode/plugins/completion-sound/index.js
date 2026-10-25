import { spawn } from "child_process";

export default {
  id: "completion-sound",
  setup: async (input) => {
    let active = true;
    let lastPlayedTime = 0;
    const DEBOUNCE_MS = 2000;

    const playSound = (reason = "STOP") => {
      const now = Date.now();
      if (now - lastPlayedTime < DEBOUNCE_MS) {
        return;
      }
      lastPlayedTime = now;

      try {
        const child = spawn(
          "/home/yar/.gemini/scripts/notify_sound.sh",
          [],
          {
            stdio: ["pipe", "ignore", "ignore"],
            detached: true,
          }
        );
        child.stdin.write(JSON.stringify({ terminationReason: reason }));
        child.stdin.end();
        child.unref();
      } catch {
        // Ignore failures
      }
    };

    (async () => {
      while (active) {
        try {
          const stream = input.event.subscribe();
          for await (const event of stream) {
            if (!active) break;
            if (!event || !event.type) continue;

            if (event.type === "session.execution.succeeded") {
              playSound("STOP");
            } else if (event.type === "session.execution.failed") {
              playSound("ERROR");
            } else if (event.type === "session.idle") {
              playSound("STOP");
            } else if (
              event.type === "session.status" &&
              event.data?.status?.type === "idle"
            ) {
              playSound("STOP");
            }
          }
        } catch {
          if (!active) break;
          await new Promise((resolve) => setTimeout(resolve, 1000));
        }
      }
    })();

    return () => {
      active = false;
    };
  },
};
