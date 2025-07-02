import argparse
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient
from azure.ai.ml.dsl import pipeline
from azure.ai.ml import Input, Output, command
from dotenv import load_dotenv

import os

load_dotenv()

def parse_args():
    parser = argparse.ArgumentParser("Deploy Training Pipeline")
    parser.add_argument("--experiment_name", type=str, help="Experiment Name")
    parser.add_argument("--compute_name", type=str, help="Compute Cluster Name")
    parser.add_argument("--data_name", type=str, help="Data Asset Name")
    parser.add_argument("--environment_name", type=str, help="Registered Environment Name")
    parser.add_argument("--enable_monitoring", type=str, help="Enable Monitoring", default="false")
    parser.add_argument("--table_name", type=str, help="ADX Monitoring Table Name", default="taximonitoring")
    return parser.parse_args()


def main():
    args = parse_args()
    print(args)
    
    credential = DefaultAzureCredential()
    # Initialize MLClient
    subscription_id = os.getenv("AZURE_SUBSCRIPTION_ID") or os.getenv("subscription_id")
    resource_group = os.getenv("AZURE_RESOURCE_GROUP") or os.getenv("resource_group")
    workspace_name = os.getenv("AZURE_ML_WORKSPACE") or os.getenv("workspace_name")
    print(f"Using subscription: {subscription_id}, resource group: {resource_group}, workspace: {workspace_name}")
    ml_client = MLClient(
        credential=credential,
        subscription_id=subscription_id,
        resource_group_name=resource_group,
        workspace_name=workspace_name
    )

    # Fetch existing environment
    env_name, _, env_version = args.environment_name.partition('@')
    print(f"Looking for environment: {env_name}@latest")
    env_obj = ml_client.environments.get(name=env_name, label="latest")
    print(f"Found environment: {env_obj.name}@{env_obj.version}")

    # Build a string reference to avoid re-registration
    env_ref = f"{env_obj.name}@latest"
    print(f"Referencing environment as: {env_ref}")

    # Validate compute
    compute = ml_client.compute.get(args.compute_name)
    print(f"Using compute: {compute.name} ({compute.type})")

    # 1. Define components using env_ref
    parent_dir = "data-science/src"

    prep_data = command(
        name="prep_data",
        display_name="prep-data",
        code=os.path.join(parent_dir, "prep"),
        command=(
            "python prep.py "
            "--raw_data ${{inputs.raw_data}} "
            "--train_data ${{outputs.train_data}} "
            "--val_data ${{outputs.val_data}} "
            "--test_data ${{outputs.test_data}} "
            "--enable_monitoring ${{inputs.enable_monitoring}} "
            "--table_name ${{inputs.table_name}}"
        ),
        environment=env_ref,
        inputs={
            "raw_data": Input(type="uri_file"),
            "enable_monitoring": Input(type="string"),
            "table_name": Input(type="string"),
        },
        outputs={
            "train_data":  Output(type="uri_folder"),
            "val_data":    Output(type="uri_folder"),
            "test_data":   Output(type="uri_folder"),
        }
    )

    train_model = command(
        name="train_model",
        display_name="train-model",
        code=os.path.join(parent_dir, "train"),
        command=(
            "python train.py "
            "--train_data ${{inputs.train_data}} "
            "--model_output ${{outputs.model_output}}"
        ),
        environment=env_ref,
        inputs={"train_data": Input(type="uri_folder")},
        outputs={"model_output": Output(type="uri_folder")}
    )

    evaluate_model = command(
        name="evaluate_model",
        display_name="evaluate-model",
        code=os.path.join(parent_dir, "evaluate"),
        command=(
            "python evaluate.py "
            "--model_name ${{inputs.model_name}} "
            "--model_input ${{inputs.model_input}} "
            "--test_data ${{inputs.test_data}} "
            "--evaluation_output ${{outputs.evaluation_output}}"
        ),
        environment=env_ref,
        inputs={
            "model_name": Input(type="string"),
            "model_input": Input(type="uri_folder"),
            "test_data":   Input(type="uri_folder"),
        },
        outputs={"evaluation_output": Output(type="uri_folder")}
    )

    register_model = command(
        name="register_model",
        display_name="register-model",
        code=os.path.join(parent_dir, "register"),
        command=(
            "python register.py "
            "--model_name ${{inputs.model_name}} "
            "--model_path ${{inputs.model_path}} "
            "--evaluation_output ${{inputs.evaluation_output}} "
            "--model_info_output_path ${{outputs.model_info_output_path}}"
        ),
        environment=env_ref,
        inputs={
            "model_name":        Input(type="string"),
            "model_path":        Input(type="uri_folder"),
            "evaluation_output": Input(type="uri_folder"),
        },
        outputs={"model_info_output_path": Output(type="uri_folder")}
    )

    # 2. Construct pipeline
    @pipeline()
    def taxi_training_pipeline(raw_data, enable_monitoring, table_name):
        prep = prep_data(raw_data=raw_data, enable_monitoring=enable_monitoring, table_name=table_name)
        train = train_model(train_data=prep.outputs.train_data)
        evaluate = evaluate_model(
            model_name="taxi-model",
            model_input=train.outputs.model_output,
            test_data=prep.outputs.test_data
        )
        register = register_model(
            model_name="taxi-model",
            model_path=train.outputs.model_output,
            evaluation_output=evaluate.outputs.evaluation_output
        )
        return {
            "pipeline_job_train_data":  prep.outputs.train_data,
            "pipeline_job_test_data":   prep.outputs.test_data,
            "pipeline_job_trained_model": train.outputs.model_output,
            "pipeline_job_score_report":  evaluate.outputs.evaluation_output,
        }

    # Format data path
    data_path = args.data_name if '@' in args.data_name else f"{args.data_name}@latest"
    print(f"Using data asset: {data_path}")

    pipeline_job = taxi_training_pipeline(
        Input(path=data_path, type="uri_file"),
        args.enable_monitoring,
        args.table_name
    )

    pipeline_job.settings.default_compute = args.compute_name
    pipeline_job.settings.default_datastore = "workspaceblobstore"

    # Submit job
    print(f"Submitting pipeline to experiment: {args.experiment_name}")
    print(f"Using environment ref: {env_ref}")
    submitted = ml_client.jobs.create_or_update(pipeline_job, experiment_name=args.experiment_name)
    print(f"Submitted job: {submitted.name}")
    if hasattr(submitted, 'studio_url'):
        print(f"Studio URL: {submitted.studio_url}")
    ml_client.jobs.stream(submitted.name)

if __name__ == "__main__":
    main()