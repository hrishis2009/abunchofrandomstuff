<?php
session_start();
if (isset ($_SESSION["loggedin"]) && $_SESSION["loggedin"] === true) {
    header("location: welcome.php");
    exit;
}
define("db_server", "localhost");
define("db_username", "root");
define("db_psw", "");
define("db_name", "Users");

$connection = mysqli_connect(db_server, db_username, db_psw, db_name);

if ($connection === false) {
  die("Connection failed: " . mysqli_connect_error()) . " . Please try again.";
}

$username = $password = "";
$username_err = $password_err = $login_err = "";
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    if (empty (trim ($_POST["username"]))) {
        $username_err = "Please enter username.";
    } else {
        $username = trim($_POST["username"]);
    }
    if (empty (trim ($_POST["password"]))) {
        $password_err = "Please enter your password.";
    } else {
        $password = trim($_POST["password"]);
    }
    if (empty ($username_err) && empty ($password_err)) {
      $sql = "SELECT id, username, password, email FROM users WHERE username = ?";
        if ($stmt = $mysqli->prepare($sql)) {
            $stmt->bind_param("s", $param_username);
            $param_username = $username;
            if ($stmt->execute()) {
                $stmt->store_result();
                if ($stmt->num_rows == 1) {                    
                    $stmt->bind_result($id, $username, $hashed_password, $email);
                    if ($stmt->fetch()) {
                        if (password_verify($password, $hashed_password)) {
                          session_start();
                            $_SESSION["loggedin"] = true;
                            $_SESSION["id"] = $id;
                            $_SESSION["username"] = $username;                            
                            header("location: welcome.php");
                        } else {
                            $login_err = "Invalid username or password.";
                        }
                    }
                } else {
                    $login_err = "Invalid username or password.";
                }
            } else {
                echo "Oops! Something went wrong. Please try again later.";
            }
            $stmt->close();
        }
    }
  $connection->close();
}
?>
