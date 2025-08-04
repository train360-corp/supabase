const crypto = require("crypto");

// --- Helpers
function base64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function signJWT(header, payload, secret) {
  const encodedHeader = base64url(JSON.stringify(header));
  const encodedPayload = base64url(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;

  const signature = crypto
    .createHmac("sha256", secret)
    .update(data)
    .digest();

  const encodedSignature = base64url(signature);
  return `${data}.${encodedSignature}`;
}

// --- Arg parsing
const args = process.argv;
const secretIndex = args.indexOf("--secret");
const typeIndex = args.indexOf("--type");

if (secretIndex === -1 || !args[secretIndex + 1] || typeIndex === -1 || !args[typeIndex + 1]) {
  console.error("Usage: node generate-jwt.js --secret <secret> --type <anon|service>");
  process.exit(1);
}

const secret = args[secretIndex + 1];
const type = args[typeIndex + 1];

if (!["anon", "service"].includes(type)) {
  console.error("Invalid --type: must be 'anon' or 'service'");
  process.exit(1);
}

const role = type === "anon" ? "anon" : "service_role";

// --- Payload
const now = Math.floor(Date.now() / 1000); // current time in seconds
const tenYears = 10 * 365 * 24 * 60 * 60;

const payload = {
  role,
  iss: "supabase",
  iat: now,
  exp: now + tenYears
};

const header = {
  alg: "HS256",
  typ: "JWT"
};

const jwt = signJWT(header, payload, secret);
console.log(jwt);