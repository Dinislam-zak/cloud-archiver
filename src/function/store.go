package main

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func saveRecord(ctx context.Context, db *dynamodb.Client, table, key string, t Task) error {
	_, err := db.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(table),
		Item: map[string]types.AttributeValue{
			"name": &types.AttributeValueMemberS{Value: t.Name},
			"url":  &types.AttributeValueMemberS{Value: t.URL},
			"key":  &types.AttributeValueMemberS{Value: key},
		},
	})
	return err
}