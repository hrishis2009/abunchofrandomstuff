$ cat ~/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 | docker login https://docker.pkg.github.com -u shanmuga1980 --password-stdin
sudo docker build -t php/login-signup/create-db .
sudo docker images
sudo docker run -p 80:80 php/login-signup/create-db
