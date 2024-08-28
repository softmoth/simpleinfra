const { CodeBuildClient, StartBuildCommand } = require("@aws-sdk/client-codebuild");

const client = new CodeBuildClient(config);

exports.handler = async function(event) {
    await client.send(new StartBuildCommand({
        projectName: 'sync-team',
    }));
};
