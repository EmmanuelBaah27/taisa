const ROUTES = Object.freeze({
  BUG: "diagnosing-bugs",
  FOGGY: "wayfinder",
  DISCOVERY: "grill-with-docs",
  ONE_SESSION: "implement",
  MULTI_SESSION: "to-spec -> to-tickets -> per-ticket implement",
  CLOSEOUT: "retro",
});

export function selectMattRoute({ workType, clarity, phase, sessions }) {
  if (workType === "bug" || workType === "performance-regression") return ROUTES.BUG;
  if (clarity === "foggy" || clarity === "stalled") return ROUTES.FOGGY;
  if (phase === "discovery") return ROUTES.DISCOVERY;
  if (phase === "closeout") return ROUTES.CLOSEOUT;
  if (phase === "implementation" && sessions === 1) return ROUTES.ONE_SESSION;
  if (phase === "implementation" && sessions === "multiple") return ROUTES.MULTI_SESSION;

  throw new Error("Insufficient workflow-routing evidence");
}
