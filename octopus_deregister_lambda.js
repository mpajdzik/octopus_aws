var aws = require("aws-sdk");
exports.handler = function(event, context) {
      if (event.detail.state != "terminated")
      context.succeed(event);
    
    var http = require('http');
  
    var instanceId = event.detail["instance-id"]; // [""] required because of the hyphen
    var currentRegion = event.region;

    console.log('EC2InstanceId =', instanceId);

    var ec2 = new aws.EC2({region: currentRegion}); //event.ResourceProperties.Region});

    var params = {
        DryRun: false,
        Filters: [
          {
            Name: 'resource-id',
            Values: [
              instanceId,
            ]
          },
          {
            Name: 'key',
            Values: [
              'OctopusMachineId',
            ]
          },
        ],
        MaxResults: 5,
    };
    console.log('Filters =', params);
    console.log("Getting MachineName for InstanceID: " + instanceId);
    
    ec2.describeTags(params, function(err, data) {

        if (err) 
        {   

            console.log(err, err.stack); // an error occurred
            context.succeed(err);
        }
        else 
        {

            console.log(data);           // successful response
            var octopusMachineId = data.Tags[0].Value;
            var fullPath = '/api/machines/' +  octopusMachineId + '?apiKey=<Octopus API Key>'; // API-XXXXXXXXXXXXXXXXXXXXXXXXXX
    
            var options = {
              host: '<Octopus Server Private IP>',
              port: 80,
              path: fullPath,
              method: 'Delete'
            };
            console.log("At parmeter section");
                
              callback = function(response) {
              var str = '';
              response.on('data', function (chunk) {
              str += chunk;
              });
            
              response.on('end', function () {
                console.log(str);
                context.succeed(str);
              });
            console.log("Making HTTP request with");  
            
            };
            http.request(options, callback).end();
            
        }
            
        }
    );
};