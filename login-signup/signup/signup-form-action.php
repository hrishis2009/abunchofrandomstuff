<?php
$uname = $_POST["uname"];
$name = $_POST["name"];
$psw = $_POST["psw"];
$servername = "192.168.1.2";
$username = "root";
$password = "";

$conn = mysqli_connect($servername, $username, $password);
if (!$conn) {
  die("Connection failed: " . mysqli_connect_error());
}

$sql = "$sql = "create Test (
firstname VARCHAR(30) NOT NULL,
lastname VARCHAR(30) NOT NULL,
email VARCHAR(50),
reg_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)";";

if ($conn->query($sql) === TRUE) {
  echo "<p>Account successfully created. Thank you.</p>";
} else {
  echo "<p>Error: " . $sql . "<br>" . $conn->error . ". Please try again.</p>";
}

$conn->close();
?>
