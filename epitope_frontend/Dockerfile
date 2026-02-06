# Step 1: Use a pre-baked Flutter image instead of Debian
# You can find community ones or build your own once and host in your Registry
FROM ghcr.io/cirruslabs/flutter:stable AS build-env

WORKDIR /app
COPY . .
ARG VERSION
# No git clone or doctor needed; the image already has it
RUN flutter build web --release --dart-define=APP_VERSION=$VERSION

FROM nginx:stable-alpine
COPY --from=build-env /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template

ENV PORT=8080
CMD ["/bin/sh", "-c", "envsubst '${PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]