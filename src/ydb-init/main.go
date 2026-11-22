package main

import (
	"context"
	"errors"
	"log"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func main() {
	endpoint := os.Getenv("DOCUMENT_API_ENDPOINT")
	table := os.Getenv("TABLE_NAME")
	if endpoint == "" || table == "" {
		log.Fatal("DOCUMENT_API_ENDPOINT and TABLE_NAME must be set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("ru-central1"))
	if err != nil {
		log.Fatalf("aws config: %v", err)
	}

	db := dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		o.BaseEndpoint = aws.String(endpoint)
	})

	_, err = db.CreateTable(ctx, &dynamodb.CreateTableInput{
		TableName: aws.String(table),
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("key"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("key"), KeyType: types.KeyTypeHash},
		},
	})
	if err != nil {
		var inUse *types.ResourceInUseException
		if errors.As(err, &inUse) {
			log.Printf("table %q already exists — nothing to do", table)
			return
		}
		log.Fatalf("create table: %v", err)
	}

	waiter := dynamodb.NewTableExistsWaiter(db)
	if err := waiter.Wait(ctx, &dynamodb.DescribeTableInput{TableName: aws.String(table)}, time.Minute); err != nil {
		log.Fatalf("wait table active: %v", err)
	}
	log.Printf("table %q created and active", table)
}