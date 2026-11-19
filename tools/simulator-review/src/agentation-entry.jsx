import React from "react";
import { createRoot } from "react-dom/client";
import { Agentation } from "agentation";

import { ReviewOverlay } from "./review-overlay.jsx";

const root = document.createElement("div");
root.id = "taisa-simulator-review";
document.body.append(root);

createRoot(root).render(
  <React.StrictMode>
    <ReviewOverlay metadata={window.__TAISA_REVIEW__} />
    <Agentation endpoint="http://localhost:4747" />
  </React.StrictMode>,
);
