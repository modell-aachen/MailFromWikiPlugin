jQuery(function($) {
    $('.wikimailto').livequery(function() {
        var $this = $(this);
        $this.click(function() {
            // defaults for dialog:
            var defaultOptions = "modal: true, draggable: true, autoOpen: true, closeOnEscape: true, resizable: true";

            // display errormessages in dialog
            var displayError = function(jqXHR) {
                var $response = $(jqXHR.responseText);
                var $message = $response.find('.foswikiTopic');
                if ($message.length == 0) $message = $response;
                var title = $response.find('h2:first, #modacHeading').text();
                title = title.replace('\n', '');
                if (!title) title = 'error';
                var $errordialog = $('<div class="jqUIDialog {' + defaultOptions + ', title: \''+title+'\'}"></div>').hide();
                $errordialog.append($message);
                $('body').append($errordialog);
            }

            // Extracts parameters encoded into a css class.
            // Parameter name and value must be separated by an underscore.
            // eg. you wan't 'cup' to be 'tea', so you add the class
            // cup_tea
            // and getParam('cup') => 'tea'
            var getParam = function(name) {
                var param = new RegExp('(?:^|\\s)' + name + '_([^\\s]+)(?:$|\\s)').exec( $this.attr('class') );
                if(param) { 
                    return encodeURIComponent(param[1]);
                }
            }

            // handeles the login-screen
            // Will return a callback function that handels an eventual login
            // screen and calls the given callback function.
            var handleLogin = function(callback) {
                return function(data, msg, jqXHR) {
                    var $data = $(data);
                    var $login = $data.find('#foswikiLogin');
                    if(!$login.length) {
                        if(callback) return callback(data, msg, jqXHR);
                        return true;
                    }
                    var $logindialog = $('<div class="jqUIDialog {width: \'600px\', '+defaultOptions+'}"></div>');
                    $logindialog.append($login);
                    $logindialog.find('form:first').ajaxForm({
                        success: handleLogin(callback),
                        beforeSubmit: function(){
                            $logindialog.dialog('close');
                            $logindialog.remove();
                        }
                    });
                    $('body').append($logindialog.hide());
                };
            }

            // display a "loading"-dialog
            var $loadingdialog = $('<div class="jqUIDialog {width: \'400px\', '+defaultOptions+'}"><div class="blockme" style="width: 100%; height: 200px;"></div></div>');
            $loadingdialog.on('dialogopen', function() {
                $loadingdialog.find('div.blockme').block();
            });
            $('body').append($loadingdialog.hide());

            // determine parameters
            var web = foswiki.getPreference('WEB');
            var topic = foswiki.getPreference('TOPIC');
            var template = getParam('template');
            if(!template) {
                alert('No template specified!');
                return;
            }
            var clicked = encodeURIComponent( $this.text() ); // text clicked on

            // callback for ajax request
            // Will display the loaded template and manage the submit
            var dialogsuccess = handleLogin(function(data, msg, jqXHR, $data) {
                // get loaded template
                var $ajaxcontents = $data.find('.dialogContents');
                if($ajaxcontents.length == 0) {
                    alert('error loading dialog template...');
                    $loadingdialog.dialog('close');
                    $loadingdialog.remove();
                    return;
                }
                var title = $data.find('span.title').text();
                var sendMessage = $data.find('span.sendingmessage').text();

                // create dialog
                var $dialog = $('<div class="jqUIDialog {width: ' + $('.foswikiTopic:first').width() + ', ' + defaultOptions + ', title: \''+title+'\'}"><div class="dialogContents"></div></div>');
                var $contents = $dialog.find('.dialogContents');

                // make the form submit in background
                var $form = $ajaxcontents.find('form:first');
                $form.ajaxForm({
                    beforeSubmit: function() {
                        $contents.block({message: sendMessage});
                        $dialog.siblings('.ui-dialog-buttonpane').block({message: ''});
                    },
                    success: handleLogin(function(data, msg, jqXHR, $data) {
                        if($data.hasClass('message')) alert($data.text());
                        $dialog.dialog('close');
                        $dialog.remove();
                    }),
                    error: function(jqXHR) {
                        displayError(jqXHR);
                        $contents.unblock();
                        $dialog.siblings('.ui-dialog-buttonpane').unblock();
                    }
                });

                // display dialog
                $contents.append($ajaxcontents);
                $loadingdialog.dialog('close');
                $loadingdialog.remove();
                $('body').append($dialog.hide());
            });

            // load template and create a dialog with it
            $.ajax({
                url: foswiki.getPreference('SCRIPTURL') + '/viewauth' + foswiki.getPreference('SCRIPTSUFFIX') + '/'+web+'/'+topic+'?template=MailFromWiki' + template + 'Dialog&customize=' + template + '&clicked=' + clicked,
                success: dialogsuccess,
                error: function(jqXHR) {
                    $loadingdialog.dialog('close');
                    $loadingdialog.remove();
                    displayError(jqXHR);
                }
            });
            return false;
        });
    });
});
