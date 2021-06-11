<?php
define('db_server', 'localhost');
define('db_username', 'root');
define('db_psw', '');
define('db_name', 'Users');

$connection = mysqli_connect($servername, $username, $password, $dbname);
if (!$connection) {
  die("Connection failed: " . mysqli_connect_error()) . " . Please try again.";
}
