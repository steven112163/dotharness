# Security

## Secrets

- Never hardcode secrets, API keys, tokens, or passwords in source code.
- Use environment variables or a secrets manager (Vault, AWS Secrets Manager, Doppler).
- Add `.env`, `.env.local`, and credential files to `.gitignore`.
- If a secret is accidentally committed, rotate it immediately.
- Use separate secrets per environment (dev, staging, prod).

## Input Validation

- Validate all external input at the system boundary: API endpoints, CLI args, file uploads.
- Use schema validation libraries (Zod, Joi, Pydantic) instead of manual checks.
- Reject invalid input early. Do not attempt to sanitize and continue.
- Enforce length limits, type constraints, and allowed character sets.
- Validate file uploads on type, size, filename, and actual content.

## Output Encoding

- Escape user-provided data before rendering in HTML, SQL, shell commands, or logs.
- Use parameterized queries for all database operations. Never interpolate SQL strings.
- Use template engines with auto-escaping turned on.
- Sanitize log messages to prevent log injection.

## Auth

- Hash passwords with bcrypt (cost 12+) or argon2. Never MD5 or SHA1 for passwords.
- Rate-limit authentication endpoints.
- Access tokens: 15 minutes max. Refresh tokens: 7 days max.
- Check authorization on every API request, not just in the UI.
- Apply least privilege to all service accounts and API keys.

## Dependencies

- Run `npm audit` / `pip audit` / `cargo audit` in CI.
- Patch critical vulnerabilities within 48 hours, high within 7 days.
- Pin exact versions in production. Use ranges only in libraries.
- Vet new dependencies before adding: check maintenance status, download volume, known issues.

## HTTP

- Set security headers: CSP, HSTS, X-Content-Type-Options, X-Frame-Options.
- HTTPS everywhere. Redirect HTTP to HTTPS.
- Cookies: HttpOnly, Secure, SameSite=Strict.
- CORS: explicit allowed origins. Never wildcard in production.
