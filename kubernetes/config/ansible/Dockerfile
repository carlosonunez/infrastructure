FROM williamyeh/ansible:ubuntu16.04
MAINTAINER Carlos Nunez <dev@carlosnunez.me>

RUN apt update && \
  apt -y install dbus && \
  mkdir -p /run/dbus && \
  pip install docker-py boto3 botocore

CMD ["/usr/sbin/init"]
