FROM alpine
MAINTAINER Carlos Nunez <dev@carlosnunez.me>

ENV CERT_UTILS_VERSION=1.2
ENV KUBECTL_VERSION=1.10.2
ENV EXTRA_BINARIES=jq,bash,curl

# Copy our kubectl initialization script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

# Install additional useful utilities
RUN apk add --update-cache $(echo "$EXTRA_BINARIES" | tr ',' ' ')

# Install cfssl and cfjson for creating a PKI and creating certificate with it.
USER root
RUN for package in cfssl cfssljson; \
  do \
    curl --output "/usr/local/bin/$package" \
      --location \
      "http://pkg.cfssl.org/R${CERT_UTILS_VERSION}/${package}_linux-amd64" && \
    chmod +x "/usr/local/bin/$package"; \
  done

# Install kubectl so you can do stuff with the k8s control plane
RUN curl --output /usr/local/bin/kubectl \
    --location \
    https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl && \
  chmod +x /usr/local/bin/kubectl

# Create a scratch directory
RUN mkdir /scratch && chown 1000 /scratch

# Make the entrypoint bash
WORKDIR /scratch
ENTRYPOINT [ "entrypoint.sh" ]
