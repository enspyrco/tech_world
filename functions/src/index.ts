/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import { onCall } from "firebase-functions/v2/https";

export const retrieveLiveKitToken = onCall(async (request) => {
  const { AccessToken } = await import("livekit-server-sdk");

  // request.auth contains auth info as the user is always authenticated
  const user = request.auth?.token; // This object includes user information such as uid
  const email = user?.email ?? "Guest";
  const uid = user?.uid ?? "guest";
  const roomName = request.data.roomName || "room";

  let livekitName = email;
  if (livekitName == null) {
    livekitName = "Guest";
  }

  const at = new AccessToken(
    process.env.LIVEKIT_API_KEY,
    process.env.LIVEKIT_API_SECRET,
    {
      identity: uid,
      name: livekitName,
      ttl: "10m", // token to expire after 10 minutes
    },
  );

  at.addGrant({ roomJoin: true, room: roomName });

  const token = await at.toJwt();

  return token;
});
