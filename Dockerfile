# Use the official Node.js 21.7.1 Alpine base image
FROM node:21.7.1-alpine AS base

# Declare and set build arguments as environment variables
ARG DATABASE_URL
ARG DIRECT_URL
#ARG SMTP_HOST
#ARG SMTP_PORT
#ARG SMTP_SECURE
#ARG SMTP_USER
#ARG SMTP_PASS
#ARG SMTP_FROM_EMAIL
#ARG AUTH_SECRET
#ARG AUTH_GOOGLE_ID
#ARG AUTH_GOOGLE_SECRET
#ARG NEXTAUTH_URL
#ARG AUTH_TRUST_HOST

# Set environment variables
ENV DATABASE_URL=${DATABASE_URL}
ENV DIRECT_URL=${DIRECT_URL}
#ENV SMTP_HOST=${SMTP_HOST}
#ENV SMTP_PORT=${SMTP_PORT}
#ENV SMTP_SECURE=${SMTP_SECURE}
#ENV SMTP_USER=${SMTP_USER}
#ENV SMTP_PASS=${SMTP_PASS}
#ENV SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL}
#ENV AUTH_SECRET=${AUTH_SECRET}
#ENV AUTH_GOOGLE_ID=${AUTH_GOOGLE_ID}
#ENV AUTH_GOOGLE_SECRET=${AUTH_GOOGLE_SECRET}
#ENV NEXTAUTH_URL=${NEXTAUTH_URL}
#ENV AUTH_TRUST_HOST=${AUTH_TRUST_HOST}

# Install dependencies only when needed
FROM base AS deps
RUN apk add --no-cache libc6-compat curl wget postgresql-client
WORKDIR /app

# Copy Prisma schema and environment files, then install dependencies
COPY prisma ./prisma
COPY messages ./messages  
# Copy environment files
#COPY .env* ./

COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./

RUN if [ -f yarn.lock ]; then \
      yarn install --frozen-lockfile && \
      yarn prisma generate && \
      (npx prisma migrate status --schema=prisma/schema.prisma --json | grep '"hasPendingMigrations":true' && yarn prisma migrate deploy || echo "No migrations to apply."); \
    elif [ -f package-lock.json ]; then \
      npm ci && \
      npx prisma generate && \
      (npx prisma migrate status --schema=prisma/schema.prisma --json | grep '"hasPendingMigrations":true' && npx prisma migrate deploy || echo "No migrations to apply."); \
    elif [ -f pnpm-lock.yaml ]; then \
      corepack enable pnpm && \
      pnpm install --frozen-lockfile && \
      pnpx prisma generate && \
      (pnpx prisma migrate status --schema=prisma/schema.prisma --json | grep '"hasPendingMigrations":true' && pnpx prisma migrate deploy || echo "No migrations to apply."); \
    else \
      echo "Lockfile not found." && exit 1; \
    fi



# Only enable on initial setup.
#RUN \
#  if [ -f yarn.lock ]; then yarn install --frozen-lockfile && yarn prisma generate &&  yarn prisma migrate resolve --applied 20241119213220_init ; \
#  elif [ -f package-lock.json ]; then npm ci && npx prisma generate && npx prisma migrate resolve --applied 20241119213220_init; \
#  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm install --frozen-lockfile && pnpx prisma generate && pnpx prisma migrate resolve --applied 20241119213220_init; \
#  else echo "Lockfile not found." && exit 1; \
#  fi
#


# Build the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN \
  if [ -f yarn.lock ]; then yarn build; \
  elif [ -f package-lock.json ]; then npm run build; \
  elif [ -f pnpm-lock.yaml ]; then pnpm run build; \
  else echo "Lockfile not found." && exit 1; \
  fi

# Production image with only necessary files
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
# Uncomment the following line in case you want to disable telemetry during runtime.
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT 3000

ENV HOSTNAME 0.0.0.0
# Run the standalone server
CMD ["node", "server.js"]
