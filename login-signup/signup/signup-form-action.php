<?php
$uname = $_POST["uname"];
$name = $_POST["name"];
$psw = $_POST["psw"];
$servername = "localhost";
$username = "username";
$password = "password";

$conn = mysqli_connect($servername, $username, $password);
if (!$conn) {
  die("Connection failed: " . mysqli_connect_error());
}

$sql = "INSERT INTO Users (username, name, password)
VALUES ($uname, $name, $psw)";

if ($conn->query($sql) === TRUE) {
  echo "<p>Account successfully created. Thank you.</p>";
} else {
  echo "<p>Error: " . $sql . "<br>" . $conn->error . ". Please try again.</p>";
}

$conn->close();
?>
