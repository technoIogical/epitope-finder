# Step 1: Use a pre-baked Flutter image instead of Debian
FROM ghcr.io/cirruslabs/flutter:3.24.0 AS build-env

WORKDIR /app
COPY . .
ARG VERSION

# Ensure dependencies are fresh and build with no icon tree-shaking
RUN flutter clean
RUN flutter pub get
RUN flutter build web --release --no-tree-shake-icons --dart-define=APP_VERSION=$VERSION

FROM nginx:stable-alpine
COPY --from=build-env /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template

ENV PORT=8080
CMD ["/bin/sh", "-c", "envsubst '${PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]