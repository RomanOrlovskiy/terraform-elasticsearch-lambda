ARG ELK_VERSION
ARG AWS_ACCESS_KEY
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_SESSION_TOKEN

FROM docker.elastic.co/elasticsearch/elasticsearch:${ELK_VERSION}

RUN elasticsearch-plugin install repository-s3 --batch #--batch required to accept security questions

#Securely pass AWS credentials to be able to create S3 repository
RUN /usr/share/elasticsearch/bin/elasticsearch-keystore create

RUN echo ${AWS_ACCESS_KEY} | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.access_key
RUN echo ${AWS_SECRET_ACCESS_KEY} | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.secret_key
RUN echo ${AWS_SESSION_TOKEN} | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.session_token
