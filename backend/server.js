const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const { GoogleGenAI } = require("@google/genai");

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json({ limit: "10mb" }));

// Gemini configuration
const apiKey = process.env.GEMINI_API_KEY;

let ai = null;

if (apiKey && apiKey !== "YOUR_GEMINI_API_KEY") {
  ai = new GoogleGenAI({
    apiKey: apiKey,
  });

  console.log("✅ Gemini API key detected.");
} else {
  console.log("⚠️ Gemini API key not configured.");
}

// Home route
app.get("/", (req, res) => {
  res.json({
    message: "AirSense Backend is running!",
    version: "1.0.0",
    geminiConfigured: !!ai,
  });
});

// Health check
app.get("/api/health", (req, res) => {
  res.json({
    backend: "online",
    geminiConfigured: !!ai,
  });
});

// Gemini air-quality analysis
app.post("/api/analyze-air", async (req, res) => {
  try {
    const {
      city,
      country,
      aqi,
      pm25,
      pm10,
      co,
      no2,
      so2,
      o3,
      temperature,
      humidity,
      windSpeed,
    } = req.body;

    if (aqi === undefined) {
      return res.status(400).json({
        error: "AQI value is required.",
      });
    }

    // If Gemini is not configured
    if (!ai) {
      return res.json({
        summary:
          "Gemini AI is not configured yet. Please add your Gemini API key to the .env file.",
        mainPollutant: "PM2.5",
        healthConsiderations:
          "Air-quality conditions should be considered before prolonged outdoor activity.",
        outdoorAdvice:
          "Check the current AQI before exercising or spending extended time outdoors.",
        recommendations: [
          "Monitor the AQI regularly.",
          "Reduce prolonged outdoor activity when AQI levels are high.",
          "Keep indoor air clean and well ventilated when appropriate.",
        ],
      });
    }

    const prompt = `
You are an air-quality assistant for a Flutter application called AirSense.

Analyze the following LIVE air-quality and weather data.

Location:
City: ${city || "Unknown"}
Country: ${country || "Unknown"}

Air Quality:
US AQI: ${aqi}
PM2.5: ${pm25} µg/m³
PM10: ${pm10} µg/m³
CO: ${co} µg/m³
NO2: ${no2} µg/m³
SO2: ${so2} µg/m³
O3: ${o3} µg/m³

Weather:
Temperature: ${temperature} °C
Humidity: ${humidity} %
Wind Speed: ${windSpeed} km/h

Return ONLY valid JSON.

Use exactly this structure:

{
  "summary": "Short explanation of the current air quality",
  "mainPollutant": "Most significant pollutant",
  "healthConsiderations": "Health considerations for the current conditions",
  "outdoorAdvice": "Advice about outdoor activities",
  "recommendations": [
    "Recommendation 1",
    "Recommendation 2",
    "Recommendation 3"
  ]
}

Do not invent medical diagnoses.
Keep the explanation simple and suitable for a general user.
`;

    const response = await ai.models.generateContent({
      model: "gemini-3.8-flash",
      contents: prompt,
    });

    let text = response.text || "";

    // Remove Markdown JSON fences if Gemini adds them
    text = text
      .replace(/```json/gi, "")
      .replace(/```/g, "")
      .trim();

    let result;

    try {
      result = JSON.parse(text);
    } catch (parseError) {
      console.log("⚠️ Gemini returned non-JSON response.");

      result = {
        summary: text,
        mainPollutant: "Unknown",
        healthConsiderations:
          "Please use the AQI and pollutant readings as general environmental information.",
        outdoorAdvice:
          "Consider the current AQI before spending extended time outdoors.",
        recommendations: [
          "Monitor the AQI regularly.",
          "Reduce prolonged outdoor activity when air quality is poor.",
          "Follow local air-quality advisories when available.",
        ],
      };
    }

    res.json(result);
  } catch (error) {
    console.error("❌ Gemini analysis error:");

    console.error(error.message);

    res.status(500).json({
      error: "Gemini analysis failed.",
      message: error.message,
    });
  }
});

// Start server
app.listen(PORT, () => {
  console.log("");
  console.log("====================================");
  console.log("🌍 AirSense Backend Started");
  console.log("====================================");
  console.log(`🚀 Server: http://localhost:${PORT}`);
  console.log(`❤️ Health: http://localhost:${PORT}/api/health`);
  console.log(`🤖 AI: POST http://localhost:${PORT}/api/analyze-air`);
  console.log("====================================");
});