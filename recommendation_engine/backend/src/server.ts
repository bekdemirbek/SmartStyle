import express, { type Request, type Response } from "express";
import { recommendPurchase } from "./recommendPurchase.js";

const app = express();
app.use(express.json({ limit: "1mb" }));

app.post("/api/recommend-purchase", async (req: Request, res: Response) => {
  try {
    const result = await recommendPurchase(req.body);
    res.json(result);
  } catch (error) {
    res.status(500).json({
      error: error instanceof Error ? error.message : "Recommendation failed",
    });
  }
});

app.listen(process.env.PORT ?? 3000, () => {
  console.log("Recommendation API is running");
});
