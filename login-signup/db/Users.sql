create database User;
backup database User
to disk = "abunchofrandomstuff/login-signup/db;
create table Info (
    uname varchar(100) not null unique,
    name varchar(100) not null unique,
    psw varchar(100) not null,
);
