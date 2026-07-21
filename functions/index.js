const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { GoogleAuth } = require("google-auth-library");
const admin = require("firebase-admin");
admin.initializeApp(); const db = admin.firestore();
const googleAuth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });

async function callGemini(contents, systemInstruction) {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  const client = await googleAuth.getClient();
  const response = await client.request({
    url: `https://aiplatform.googleapis.com/v1/projects/${projectId}/locations/us-central1/publishers/google/models/gemini-2.5-flash:generateContent`,
    method: "POST",
    data: {
        system_instruction: { parts: [{ text: systemInstruction }] },
        contents,
        generationConfig: { temperature: 0.25, maxOutputTokens: 900 },
    },
  });
  const json = response.data;
  return json.candidates?.[0]?.content?.parts?.map((part) => part.text || "").join("") || "No response generated.";
}

const systemGuide = `You are the embedded support assistant for a multi-platform POS system.
The system covers POS checkout, products, stock, purchases and attachments, expenses, financial accounts and fees, accounting ledger, payroll and contracts, assets and depreciation, sales, online orders, delivery staff and tracking, reports, role/CRUD permissions, notifications, customer marketplace, and administrator support tickets.
Give short, safe, practical instructions based only on supplied business context. Never claim to execute a transaction. For destructive, payment, payroll, stock, or checkout actions, tell the user to confirm in the relevant screen. Answer in English or Swahili matching the user.`;

exports.aiSupportChat = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  const message = String(request.data?.message || "").trim();
  if (!message || message.length > 2000) throw new HttpsError("invalid-argument", "Enter a valid message.");
  const history = Array.isArray(request.data?.history) ? request.data.history.slice(-10) : [];
  const contents = [...history.map((item) => ({ role: item.role === "model" ? "model" : "user", parts: [{ text: String(item.text || "") }] })), { role: "user", parts: [{ text: message }] }];
  return { text: await callGemini(contents, systemGuide) };
});

exports.aiBusinessAdvice = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  const context = request.data?.context || {};
  const prompt = `Analyze this POS business summary and return: 1) key insight, 2) cost reduction advice, 3) stock action, 4) cash-flow warning, 5) best-practice action. Use exact supplied figures and do not invent data.\n${JSON.stringify(context)}`;
  return { text: await callGemini([{ role: "user", parts: [{ text: prompt }] }], systemGuide) };
});

exports.recognizeProductImage = onCall({ memory: "512MiB" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  const imageBase64 = String(request.data?.imageBase64 || "");
  const mimeType = String(request.data?.mimeType || "image/jpeg");
  if (!imageBase64 || imageBase64.length > 8_000_000) throw new HttpsError("invalid-argument", "Image is missing or too large.");
  const productNames = Array.isArray(request.data?.productNames) ? request.data.productNames.slice(0, 300) : [];
  const prompt = `Identify the retail product in this image. Choose the closest item from this inventory when possible: ${JSON.stringify(productNames)}. Return only compact JSON with keys detectedText, productName, searchQuery, confidence (0 to 1). Do not include markdown.`;
  const text = await callGemini([{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: mimeType, data: imageBase64 } }] }], systemGuide);
  try { return JSON.parse(text.replace(/^```json|```$/g, "").trim()); } catch (_) { return { detectedText: text, productName: "", searchQuery: text, confidence: 0 }; }
});
async function notifyUsers(userIds,title,body,type,data={}) { const ids=[...new Set(userIds.filter(Boolean))]; if(!ids.length)return; const users=await Promise.all(ids.map(id=>db.collection("users").doc(id).get())); const tokens=[]; const batch=db.batch(); users.forEach(user=>{if(!user.exists)return; const n=db.collection("notifications").doc(); batch.set(n,{recipientId:user.id,title,body,type,data,read:false,createdAt:admin.firestore.FieldValue.serverTimestamp()}); tokens.push(...(user.data().fcmTokens||[]));}); await batch.commit(); if(tokens.length) await admin.messaging().sendEachForMulticast({tokens:[...new Set(tokens)],notification:{title,body},data:Object.fromEntries(Object.entries({type,...data}).map(([k,v])=>[k,String(v)])),android:{priority:"high",notification:{sound:"default",channelId:"pos_alerts"}},apns:{payload:{aps:{sound:"default"}}}}); }
exports.newBusinessOwner=onDocumentCreated("businesses/{businessId}",async event=>{const b=event.data.data();const owners=await db.collection("users").where("role","==","system_owner").get();await notifyUsers(owners.docs.map(d=>d.id),"New business registration",`${b.ownerName||"An owner"} registered ${b.name||"a business"}.`,"new_business",{businessId:event.params.businessId});});
exports.newOnlineOrder=onDocumentCreated("customer_orders/{orderId}",async event=>{const o=event.data.data(),recipients=[];for(const businessId of o.shopIds||[]){const users=await db.collection("users").where("businessId","==",businessId).where("role","==","super_admin").get();recipients.push(...users.docs.map(d=>d.id));}await notifyUsers(recipients,"New online order",`${o.customerName||"A customer"} placed a new order.`,"new_order",{orderId:event.params.orderId});});
exports.deliveryAssignment=onDocumentUpdated("customer_orders/{orderId}",async event=>{const before=event.data.before.data(),after=event.data.after.data();if(after.deliveryBoyId&&after.deliveryBoyId!==before.deliveryBoyId)await notifyUsers([after.deliveryBoyId],"New delivery assignment",`Order ${event.params.orderId.substring(0,8).toUpperCase()} was assigned to you.`,"delivery_assignment",{orderId:event.params.orderId});});
exports.supportMessage=onDocumentCreated("support_tickets/{ticketId}/messages/{messageId}",async event=>{const m=event.data.data(),ticket=await db.collection("support_tickets").doc(event.params.ticketId).get();if(!ticket.exists)return;let recipients=[];if(m.senderRole==="system_owner")recipients=[ticket.data().ownerId];else{const owners=await db.collection("users").where("role","==","system_owner").get();recipients=owners.docs.map(d=>d.id);}await notifyUsers(recipients,"Support message",`${m.senderName||"Support"}: ${m.message||"New message"}`,"support_message",{ticketId:event.params.ticketId});});
