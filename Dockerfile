FROM ubuntu:13.10
MAINTAINER Walt Woods <woodswalben@gmail.com>

RUN echo "deb http://archive.ubuntu.com/ubuntu saucy main universe" > /etc/apt/sources.list
RUN apt-get update

RUN apt-get install -y git python-pip
RUN pip install cherrypy
RUN pip install requests

ADD . /app
RUN touch /app/app_local.ini

EXPOSE 8080
WORKDIR /app
ENTRYPOINT ["/usr/bin/python", "run.py"]

