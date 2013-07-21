(function() {

// when the DOM loads
$(document).ready(function() {
    // click handler for "Try Julia Now" button
    $("a#submit_button").click(function() {
        // submit the form
        $("form#session_form").submit();
    });

    // submit the form when the user hits enter
    $("input#user_name").keydown(function(e) {
        if (e.keyCode == 13) {
            $("form#session_form").submit();
            return false;
        }
    });
    $("input#session_name").keydown(function(e) {
        if (e.keyCode == 13) {
            $("form#session_form").submit();
            return false;
        }
    });

    // called when the server has responded
    function callback(jqXHR, textStatus) {
        status = jqXHR.status;
        if (status == 201) {
            window.location.replace("/repl.htm");
        } else {
            alert("Failed to create new session")
        }
    }

    // form handler
    $("form#session_form").submit(function() {
        // Request a new session
        $.ajax("/session/new",{
            complete: callback,
            type: "POST",
            data: $("form#session_form").serialize()});
        return false;
    });

    // focus the first input box
    $("input#user_name").focus();
}); })()