# What Should I Buy? Recommendation Engine Scaffold

This scaffold contains a Node.js recommendation backend and a React Native flow.

Backend pieces:
- `src/types.ts`: shared types
- `src/intentParser.ts`: text + filter intent parsing
- `src/combinationValidity.ts`: smart combination validity rules
- `src/fallbackEngine.ts`: local rule-based fallback
- `src/geminiClient.ts`: Gemini JSON prompt and response validation
- `src/recommendPurchase.ts`: primary Gemini + fallback orchestration

Frontend pieces:
- `frontend/WhatShouldIBuyFlow.tsx`: 3-step React Native UI flow

The backend expects `GEMINI_API_KEY` in the environment.
