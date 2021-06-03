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
    navigator.geolocation.getCurrentPosition(myMap);
  } else {
    document.getElementById("userLocMapErr").innerHTML = "Geolocation is not supported by this browser.";
    document.getElementById("userLocMapErr").style.color = "#ff0000";
  }
}

function myMap() {
var mapProp= {
  center:new google.maps.LatLng(position.coords.latitude,position.coords.longitude),
  zoom:5,
};
var map = new google.maps.Map(document.getElementById("googleMap"),mapProp);
}

var marker = new google.maps.Marker({position: {lat: position.coords.latitude , lng: position.coords.longitude}});

marker.setMap(map);
