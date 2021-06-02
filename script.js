var prevScrollpos = window.pageYOffset;

window.onscroll = function() {
var currentScrollPos = window.pageYOffset;
  if (prevScrollpos > currentScrollPos) {
    document.getElementById("navbar").style.top = "0";
  } else {
    document.getElementById("navbar").style.top = "-50px";
  }
  prevScrollpos = currentScrollPos;
}

function naventer(x) {
  x.style.animation = "mouseenter 0.75s 1";
  x.style.animationFillMode = "forwards";
}

function navleave(x) {
  x.style.animation = "mouseleave 0.45s 1";
  x.style.animationFillMode = "forwards";
}

function getLocation() {
  if (navigator.geolocation) {
    navigator.geolocation.getCurrentPosition(showPosition);
  } else {
    document.getElementById("userLocMapErr").innerHTML = "Geolocation is not supported by this browser.";
  }
}

function showPosition(position) {
  document.getElementById("userLocMap").src = "https://www.google.com/maps/@" + position.coords.latitude + "," +  position.coords.longitude + ",78m/data=!3m1!1e3";
}
