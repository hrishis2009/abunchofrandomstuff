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

var y = document.getElementById("geolocationbtn");
function getLocation()
  {
  if (navigator.geolocation)
    {
    navigator.geolocation.getCurrentPosition(showPosition,showError);
    }
  else{x.innerHTML="Geolocation is not supported by this browser.";}
  }

function showPosition(position)
  {
  var lat = position.coords.latitude;
  var lon = position.coords.longitude;
  var latlon = new google.maps.LatLng(lat, lon)
  var mapholder = document.getElementById("mapholder")
  mapholder.style.height='250px';
  mapholder.style.width='100%';

  var myOptions = {
  center:latlon,zoom:14,
  mapTypeId:google.maps.MapTypeId.ROADMAP,
  mapTypeControl:false,
  navigationControlOptions:{style:google.maps.NavigationControlStyle.SMALL}
  };
  var map = new google.maps.Map(document.getElementById("mapholder"),myOptions);
  var marker = new google.maps.Marker({position:latlon,map:map,title:"You are here!"});
  }

function showError(error)
  {
  switch(error.code) 
    {
    case error.PERMISSION_DENIED:
      y.innerHTML = "User denied the request for Geolocation."
      break;
    case error.POSITION_UNAVAILABLE:
      y.innerHTML = "Location information is unavailable."
      break;
    case error.TIMEOUT:
      y.innerHTML =" The request to get user location timed out."
      break;
    case error.UNKNOWN_ERROR:
      y.innerHTML = "An unknown error occurred."
      break;
    }
  }
