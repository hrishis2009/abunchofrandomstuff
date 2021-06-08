<?php
$uname = $_POST["uname"];
$name = $_POST["name"];
$psw = $_POST["psw"];
$servername = "192.168.1.2";
$username = "root";
$password = "";
$dbname = "apps";

$conn = mysqli_connect($servername, $username, $password, $dbname);
if (!$conn) {
  die("Connection failed: " . mysqli_connect_error());
}

$sql = "create Test (
                  firstname varchar(30) not NULL,
                  lastname varchar(30) not NULL,
                  email varchar(50) not null,
                  )";

if ($conn->query($sql) === TRUE) {
  echo "<p>Account successfully created. Thank you.</p>";
} else {
  echo "<p>Error: " . $sql . "<br>" . $conn->error . ". Please try again.</p>";
}

$conn->close();
?>
