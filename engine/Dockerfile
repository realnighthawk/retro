FROM golang:1.26.1 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /retro-api ./cmd/retro-api
FROM gcr.io/distroless/static:nonroot
COPY --from=build /retro-api /retro-api
ENV LISTEN_ADDR=0.0.0.0:8092
EXPOSE 8092
ENTRYPOINT ["/retro-api"]
