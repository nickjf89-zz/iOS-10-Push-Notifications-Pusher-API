var Pusher = require("pusher");

var pusher = new Pusher({
  appId: "",
  key: "",
  secret: ""
});

pusher.notify(['donuts'], {
  apns: {
    aps: { 
      alert: { 
        title: "Title goes here!", 
        subtitle: "Subtitle goes here!", 
        body: "Body goes here!"
        }, 
        "mutable-content": 1,
        category: "pusher"
      },
    data: {
      "attachment-url": "https://pusher.com/static_logos/320x320.png"
    } 
  },
  webhook_url: "https://example.com/endpoint",
  webhook_level: "INFO"
});