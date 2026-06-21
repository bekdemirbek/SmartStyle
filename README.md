# SmartStyle

SmartStyle is a Flutter wardrobe assistant that helps users manage their clothes, generate outfit ideas, analyze wardrobe gaps, and plan travel outfits with Firebase-backed data and AI-powered suggestions.

## Features

- User authentication with Firebase Auth and Google Sign-In
- Wardrobe management with image upload, item details, categories, colors, seasons, and usage tracking
- AI outfit suggestions powered by Firebase Cloud Functions and Gemini
- Wardrobe gap analysis with purchase suggestions
- Travel mode for packing and day-by-day outfit planning
- Weather-aware outfit recommendation logic
- Favorite and saved outfit flows
- Firebase Firestore and Storage integration
- Local fallback recommendation logic when AI services are unavailable

## Tech Stack

- Flutter / Dart
- Firebase Auth
- Cloud Firestore
- Firebase Storage
- Firebase Cloud Functions
- TypeScript
- Google Gemini API
- Google ML Kit Image Labeling
- Geolocator and weather-based services

## Project Structure

```text
lib/
  models/       Data models used by the app
  screen/       Main application screens
  services/     Firebase, AI, weather, wardrobe, and recommendation services
  widgets/      Reusable UI components

functions/
  src/          Firebase Cloud Functions for AI features

recommendation_engine/
  backend/      TypeScript recommendation engine prototype
  frontend/     Purchase recommendation flow prototype
```

## Getting Started

Install Flutter dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

Install Cloud Functions dependencies:

```bash
cd functions
npm install
```

Build Cloud Functions:

```bash
npm run build
```

## Environment Notes

AI features use Firebase secrets for external API keys. For deployment, configure the required secrets in Firebase instead of committing private keys to the repository.

Example:

```bash
firebase functions:secrets:set GEMINI_API_KEY
```

## Status

This project is under active development and is intended as a portfolio project demonstrating Flutter, Firebase, AI integration, and recommendation-system logic.
