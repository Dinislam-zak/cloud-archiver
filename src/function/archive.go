package main

import (
	"archive/zip"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func archiveToBucket(ctx context.Context, up *manager.Uploader, bucket, key, fileURL string) error {
	pr, pw := io.Pipe()

	go func() {
		pw.CloseWithError(buildZip(ctx, fileURL, pw))
	}()

	_, err := up.Upload(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(key),
		Body:        pr,
		ContentType: aws.String("application/zip"),
	})
	if err != nil {
		pr.CloseWithError(err)
		return err
	}
	return nil
}

func buildZip(ctx context.Context, fileURL string, w io.Writer) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fileURL, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download: status %s", resp.Status)
	}

	zw := zip.NewWriter(w)
	entry, err := zw.CreateHeader(&zip.FileHeader{
		Name:   entryName(fileURL),
		Method: zip.Deflate,
	})
	if err != nil {
		return err
	}
	if _, err := io.Copy(entry, resp.Body); err != nil {
		return err
	}
	return zw.Close()
}

func entryName(fileURL string) string {
	u, err := url.Parse(fileURL)
	if err != nil {
		return "file"
	}
	name := path.Base(u.Path)
	if name == "." || name == "/" || strings.TrimSpace(name) == "" {
		return "file"
	}
	return name
}