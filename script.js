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

function subnaventer(x) {
  x.style.visibility = "visible";
  document.getElementById("subnavbarbutton").style.animation = "mouseeenter 0.75s 1";
  document.getElementById("subnavbarbutton").style.animationFillMode = "forwards";
}

function subnavleave(x) {
  x.style.visibility = "hidden";
  document.getElementById("subnavbarbutton").style.animation = "mouseleave 0.45s 1";
  document.getElementById("subnavbarbutton").style.animationFillMode = "forwards";
}

function subnavleave(x) {
  x.style.visibility = "hidden";
  document.getElementById("subnavbarbutton").style.animation = "mouseleave 0.45s 1";
  document.getElementById("subnavbarbutton").style.animationFillMode = "forwards";
}

function getLocation() {
  if (navigator.geolocation) {
    navigator.geolocation.getCurrentPosition(showPosition, showError);
  } else { 
    document.getElemenById("mapholder").src = "https://www.google.com/maps/place//@" + position.coords.lattitude + "," + position.coords.longitude + ",17z"
}

function showError(error)
  {
  switch(error.code) 
    {
    case error.PERMISSION_DENIED:
      document.getElemenById("mapholder").alt = "User denied the request for Geolocation."
      break;
    case error.POSITION_UNAVAILABLE:
      document.getElemenById("mapholder").alt = "Location information is unavailable."
      break;
    case error.TIMEOUT:
      document.getElemenById("mapholder").alt =" The request to get user location timed out."
      break;
    case error.UNKNOWN_ERROR:
      document.getElemenById("mapholder").alt = "An unknown error occurred."
      break;
    }
  }
