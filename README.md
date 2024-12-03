# Deployment

Requirements:
- mkcert
- openssl

Clone repository:
- ```git clone git@github.com:CodeClarityCE/deployment.git```

Create jwt tokens and certs:
- ```make setup-jwt```
- ```make setup-tls```

Add localtest.io to /etc/hosts:
- ```sudo bash -c 'echo "127.0.0.1 localtest.io" >> /etc/hosts'```