This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

## GreenGuard device and AI network settings

- Web scan requests go through the same-origin Next.js `/api/scan` route; the browser never calls the HTTP AI server directly, avoiding HTTPS mixed-content restrictions. The server-side default is the verified `http://185.133.48.73`; Web deployments can override it with `GREENGUARD_AI_URL`.
- Flutter uses the centralized `lib/config/greenguard_network_config.dart` value. The verified HTTP endpoint is the default for the native Android app. If a secure HTTPS endpoint is provisioned for direct clients, override it with `--dart-define=GREENGUARD_AI_BASE_URL=https://your-ai-host`.
- The verified endpoints are `GET /health` and multipart `POST /scan` with field `image`. A POST without an image returns the expected `image_missing` JSON error.
- ESP32-CAM discovery and the soil sensor's UDP discovery remain local-network settings in that Flutter config. They are separate from the Contabo AI address. Soil readings are marked live only after the device's `/soil` response contains valid moisture, raw ADC, status, and matching device IP values.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
