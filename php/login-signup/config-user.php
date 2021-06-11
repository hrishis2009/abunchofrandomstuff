<?php
define("db_server", "localhost");
define("db_username", "root");
define("db_psw", "");
define("db_name", "Users");

$connection = mysqli_connect(db_server, db_username, db_psw, db_name);

if ($connection === false) {
  die("Connection failed: " . mysqli_connect_error()) . " . Please try again.";
}
?>
