function renderTestsList(jobs, is_operator, restart_url) {

    var table = $('#results').DataTable( {
	"dom": 'l<"#toolbar">frtip',
	"lengthMenu": [[10, 25, 50], [10, 25, 50]],
	"ajax": {
	    "url": "/tests/list_ajax",
	    "type": "POST", // we use POST as the URLs can get long
	    "data": function(d) {
		var ret = {
		    "relevant": $('#relevantfilter').prop('checked')
		};
		if (jobs != null) {
		    ret['jobs'] = jobs;
		    ret['initial'] = 1;
		}
		// reset for reload
		jobs = null;
		return ret;
	    }
	},
	// no initial resorting
	"order": [],
	"columns": [
	    { "data": "name" },
	    { "data": "test" },
	    { "data": "deps" },
	    { "data": "testtime" },
	    { "data": "result_stats" },
	],
	"columnDefs": [
	    { targets: 0,
	      className: "name",
	      "render": function ( data, type, row ) {
		  var name = 'Build' + row['build'];
		  name += " of ";
		  return name + row['distri'] + "-" + row['flavor'] + "." + row['arch'];
	      },
	    },
	    { targets: 1,
	      className: "test",
	      "render": function ( data, type, row ) {
		  if (type === 'display') {
		      html = '<a class="overview_' + row['result'] + '" href="/tests/' + row['id'] + '">' + data + '</a>';
		      if (row['clone']) {
                          html += ' <a href="/tests/' + row['clone'] + '">(restarted)</a>';
                      } else if (is_operator) {
			  var url = restart_url.replace('REPLACEIT', row['id']);
                          html += ' <a data-method="POST" data-remote="true" class="api-restart" href="' + url + '">' +
                              '<i class="fa fa-repeat" title="Restart Job"></i></a>'
		      }
                      return html;
		  } else {
		      return data;
		  }
              },
	    },
	    { targets: 3,
	      "render": function ( data, type, row ) {
		  if (type === 'display')
		      return jQuery.timeago(data + " UTC");
		  else
		      return data;
	      }
	    },
	    { targets: 4,
	      "render": function ( data, type, row ) {
		    if (type === 'display') {
		      var html = '' 
		      if (row['state'] === 'done') {
		          html += data['passed'] + "<i class='fa fa-star'></i>";
		          if (data['dents']) {
			      html +=  " " + data['dents'] + "<i class='fa fa-star-half-empty'></i> ";
		          }
		          if (data['failed']) {
			      html +=  " " + data['failed'] + "<i class='fa fa-star-o'></i> ";
		          }
		          if (data['none']) {
			      html +=  " " + data['none'] + "<i class='fa fa-ban'></i> ";
		          }
		      }
		      if (row['state'] === 'cancelled') {
		          html += "<i class='fa fa-times'></i>";
		      }
		      if (row['deps']) {
		          if (row['result'] === 'skipped' ||
		              row['result'] === 'parallel_failed') {
		              html += "<i class='fa fa-chain-broken'></i>";
		          }
		          else {
		              html += "<i class='fa fa-link'></i>";
		          }
		      }
                      return '<a class="overview_' + row['result'] + '" href="/tests/' + row['id'] + '">' + html + '</a>';
		  } else {
		      return (parseInt(data['passed']) * 10000) + (parseInt(data['dents']) * 100) + parseInt(data['failed']);
		  }
              }
	    },
	],
    } );
    $("#relevantbox").detach().appendTo('#toolbar');
    $('#relevantbox').css('display', 'inherit');
    // Event listener to the two range filtering inputs to redraw on input
    $('#relevantfilter').change( function() {
	$('#relevantbox').css('color', 'cyan');
        table.ajax.reload(function() {
	    $('#relevantbox').css('color', 'inherit');
	} );
    } );
    $(document).on("click", '.api-restart', function() {
	var link = $(this);
	$.post(link.attr("href")).done( function( data ) { console.log(link); $(link).replaceWith('(restarted)'); });
    });
};