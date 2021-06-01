var prevScrollpos = window.pageYOffset;
var lat = position.coords.latitude;
var lng = position.coords.longitude;

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

function myMap() {
var mapProp= {
  center:new google.maps.LatLng(lat,lng),
  zoom:5,
};
var map = new google.maps.Map(document.getElementById("googleMap"),mapProp);
}
