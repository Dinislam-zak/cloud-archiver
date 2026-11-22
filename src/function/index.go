package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
)

const (
	region     = "ru-central1"
	s3Endpoint = "https://storage.yandexcloud.net"
)

type Event struct {
	Messages []struct {
		Details struct {
			Message struct {
				Body string `json:"body"`
			} `json:"message"`
		} `json:"details"`
	} `json:"messages"`
}

type Task struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

func (t Task) validate() error {
	if t.Name == "" {
		return fmt.Errorf("task: name is empty")
	}
	u, err := url.Parse(t.URL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return fmt.Errorf("task: invalid url %q", t.URL)
	}
	return nil
}

type app struct {
	uploader *manager.Uploader
	ddb      *dynamodb.Client
	bucket   string
	table    string
}

var (
	once    sync.Once
	a       app
	initErr error
)

func getApp(ctx context.Context) (*app, error) {
	once.Do(func() {
		bucket := os.Getenv("BUCKET")
		docEndpoint := os.Getenv("DOCUMENT_API_ENDPOINT")
		table := os.Getenv("TABLE_NAME")
		if table == "" {
			table = "archives"
		}
		if bucket == "" || docEndpoint == "" {
			initErr = fmt.Errorf("BUCKET and DOCUMENT_API_ENDPOINT must be set")
			return
		}

		cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
		if err != nil {
			initErr = err
			return
		}

		s3client := s3.NewFromConfig(cfg, func(o *s3.Options) {
			o.BaseEndpoint = aws.String(s3Endpoint)
			o.UsePathStyle = true
		})

		a = app{
			uploader: manager.NewUploader(s3client, func(u *manager.Uploader) {
				u.PartSize = 8 * 1024 * 1024
				u.Concurrency = 1
			}),
			ddb: dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
				o.BaseEndpoint = aws.String(docEndpoint)
			}),
			bucket: bucket,
			table:  table,
		}
	})
	return &a, initErr
}

func Handler(ctx context.Context, event Event) error {
	ctx, cancel := context.WithTimeout(ctx, 9*time.Minute)
	defer cancel()

	ap, err := getApp(ctx)
	if err != nil {
		return fmt.Errorf("init: %w", err)
	}

	for _, m := range event.Messages {
		var t Task
		if err := json.Unmarshal([]byte(m.Details.Message.Body), &t); err != nil {
			return fmt.Errorf("bad message body: %w", err)
		}
		if err := t.validate(); err != nil {
			return err
		}
		if err := process(ctx, ap, t); err != nil {
			return err
		}
	}
	return nil
}

func process(ctx context.Context, ap *app, t Task) error {
	id, err := uuid.NewV7()
	if err != nil {
		return fmt.Errorf("uuid v7: %w", err)
	}
	key := id.String() + ".zip"

	if err := archiveToBucket(ctx, ap.uploader, ap.bucket, key, t.URL); err != nil {
		return fmt.Errorf("archive %q: %w", t.URL, err)
	}
	if err := saveRecord(ctx, ap.ddb, ap.table, key, t); err != nil {
		return fmt.Errorf("ydb put %q: %w", key, err)
	}

	log.Printf("OK: name=%q url=%q key=%s", t.Name, t.URL, key)
	return nil
}