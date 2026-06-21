import { fallbackRecommendPurchase } from "./fallbackEngine.js";
import { getGeminiRecommendations } from "./geminiClient.js";
import { parsePurchaseIntent } from "./intentParser.js";
import { RecommendRequest, RecommendResponse } from "./types.js";

export async function recommendPurchase(
  request: RecommendRequest,
): Promise<RecommendResponse> {
  const intent = parsePurchaseIntent({
    text: request.text,
    selectedOccasion: request.selectedOccasion,
    selectedCategory: request.selectedCategory,
    wardrobe: request.wardrobe,
  });

  if (intent.follow_up_question) {
    return {
      intent,
      recommendations: [],
      fallback: false,
      notice: intent.follow_up_question,
    };
  }

  const apiKey = process.env.GEMINI_API_KEY;

  if (apiKey) {
    try {
      const recommendations = await getGeminiRecommendations({
        apiKey,
        wardrobe: request.wardrobe,
        intent,
        currentCombinations: request.currentCombinations,
      });

      return { intent, recommendations, fallback: false };
    } catch (error) {
      const recommendations = fallbackRecommendPurchase({
        wardrobe: request.wardrobe,
        intent,
      });

      return {
        intent,
        recommendations,
        fallback: true,
        notice: "AI öneri geçici olarak devre dışı; yerel stil motoru kullanıldı.",
      };
    }
  }

  return {
    intent,
    recommendations: fallbackRecommendPurchase({
      wardrobe: request.wardrobe,
      intent,
    }),
    fallback: true,
    notice: "AI anahtarı bulunamadı; yerel stil motoru kullanıldı.",
  };
}
