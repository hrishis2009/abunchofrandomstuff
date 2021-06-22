var prevScrollpos = window.pageYOffset;
window.setInterval(getDateTime, 1000);
var DifferenceFromUTC;

window.onscroll = function() {
var currentScrollPos = window.pageYOffset;
  if (prevScrollpos > currentScrollPos) {
    document.getElementById("navbar").style.top = "0";
  } else {
    document.getElementById("navbar").style.top = "-50px";
  };
  prevScrollpos = currentScrollPos;
};

function getDateTime() {
  var dateTime = document.getElementById("dateTime").innerHTML;
  var d = new Date();
  var weekdays = new Array(7);
  weekdays[0] = "Sunday";
  weekdays[1] = "Monday";
  weekdays[2] = "Tuesday";
  weekdays[3] = "Wednesday";
  weekdays[4] = "Thursday";
  weekdays[5] = "Friday";
  weekdays[6] = "Saturday";
  var months = new Array(12);
  months[0] = "January";
  months[1] = "February";
  months[2] = "March";
  months[3] = "April";
  months[4] = "May";
  months[5] = "June";
  months[6] = "July";
  months[7] = "August";
  months[8] = "September";
  months[9] = "October";
  months[10] = "November";
  months[11] = "December";
  var dayOfMonth = d.getDate();
  var month = months[d.getMonth()];
  var year = d.getFullYear();
  var day = weekdays[d.getDay();]
  var clockTime = d.toLocaleTimeString();
  dateTime = day + ", " + month + " " + dayOfMonth + "," + year + ", " + clockTime;
};
