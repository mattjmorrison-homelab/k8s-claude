# release and test each have their own external FROM instead of extending
# a shared base stage: kaniko pushes a Docker-v2-schema manifest (which
# zot rejects with 415/MANIFEST_INVALID) when a pushed --target stage's
# own FROM references another Dockerfile stage rather than an external
# image, confirmed by reproducing locally against a throwaway registry
# (see graph-hdmi-switch, the precedent this repo mirrors).

FROM node:20-bookworm-slim@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0 AS test
WORKDIR /app
COPY package.json ./
COPY package-lock.json ./
RUN npm ci
COPY src ./src
ENTRYPOINT ["npm", "test"]

FROM node:20-bookworm-slim@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0 AS release
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
ENTRYPOINT ["node", "src/index.js"]
