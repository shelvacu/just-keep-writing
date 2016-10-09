window.game = {};
game.ws = new WebSocket("ws://127.0.0.1:8080/");
game.send = function(data){
    game.ws.send(JSON.stringify(data));
};
game.ws.onclose = function(){
    alert('Connection lost :(');
}
game.ws.onmessage = function(event){
    var msg = JSON.parse(event.data);
    console.log('msg', msg);
    switch(msg.type){
    case "debug":
	//console.log("debug message:", msg);
	break;
    case "set_name_response":
	if(!msg.result){
	    alert("That name is already taken!");
	}else{
	    $("#name-chooser-box").hide();
	    $("#game").show();
	    $("#user-name").text(game.name);
	}
	break;
    case "status":
	var now = new Date();
	var status = msg.status
	game.text = status.text;
	game.timeout_at = new Date(now.getTime()+(status.timeleft*1000));
	if(!game.authoring)
	    $("#text-box").text(game.text);
	game.authoring = (game.name == status.playing);
	$("#playing-name").text(status.playing);
	break;
    //case "update_response":
    default:
	//console.log("unrec msg", msg);
	break;
    }
}

game.text = "";
game.name = null;
game.authoring = false;				   
game.timeout_at = new Date();
game.timer_interval = setInterval(function(){
    var now = new Date();
    var timeleft;
    if(now > game.timeout_at)
	timeleft = 0;
    else
	timeleft = Math.round((game.timeout_at - now)/1000);
    $("#time-left").text(timeleft + " second(s)");
},100);

$(function(){
    $("#name-submit").click(function(){
	game.name = $("#name-input").val();
	game.send({type: "set_name", name: game.name});
    });

    $(document.body).on('keypress', function(e){
	console.log("registering keypress");
	if(!game.authoring)
	    return;
	console.log("am authoring, continuing to send keypress");
	var ch = e.key;
	if(ch == "Backspace"){
	    if(game.text.length >= 2){
		game.text = game.text.slice(0,-1);
		game.send({type: "update", change_type: "backspace"})
	    }
	}else{
	    if(ch == "Enter")
		ch = "\n";
	    if(ch.length == 1){
		game.text += ch
		game.send({type: "update", change_type: "character", character: ch});
	    }else{
		console.log("undealt-with character", ch);
	    }
	}
	$("#text-box").text(game.text);
    });
});
