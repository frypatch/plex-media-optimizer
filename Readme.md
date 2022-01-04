# DVD Upscale

## Purpose
The DVD upscaler is designed to upscale provided DVD quality videos to 720p.

## Example Usage
```sh
go run cmd/client/* -h
go run cmd/client/* -path="[Path]"
go run cmd/client/* -dryRun -path="[Path]"
go run cmd/client/* -skipCleanup -skipDenoise -path="[Path]"
```

## How Optimizing Movies Works

The DVD upscaler will scan a supplied directory path for subdirectories that contain a movie file whose name (less the media extension) exactly maches the subdirectory name. When found, the movie file will be copied to a local temporary directory, analyzed, and (if necessory) re-encoded.

In the case that the subdirectory does not contain a movie whose name exactly matches the subdirectory name the DVD upscaler will search the subdirectory for a movie file whose name (less the media extension) ends with `- pt1`. If a match is found the DVD upscaler will go into concatination mode which means that it will concatinate all videos in the subdirectory that end in ` -pt1` through ` -pt9000` into a single movie. Chapters names based on the concatinated movies will be added to the final movie to provide a convenient way to jump to the start of a specific concatinated video. The final video will then be copied to a local temporary directory, analyzed, and (if necessory) re-encoded.

Because all media is copied to a local temporary directory the media optimizer is able to optimize remote directories that are mounted to your local filesystem. Thus, you can use rclone.org to virturaly mount your remote cloud storage system to your local file system and then supply the path to this virtural mount to the media optimizer to optimize all the movies.

## FAQ

### Why was the CRF set to 16?
It is widely accepted that in most situations a video re-encoded using a CRF value of 16 is precieved as visually lossless when compared to its source. Additionally, in most cases, the resulting bitrate of a DVD re-encoded using the HEVC codec at a CRF of 16 will be under 2000kbps.

### Why bitrate limit movies to 2000kbps?
A couple of factors played into this decision. The first is that many Plex clients default to a 2000kbps bandwidth limit. Staying underneath this limit will allow a Plex server to serve these movies to the client without first transcoding the movie to a lower bitrate. The second reason that the 2000kbps limit was choosen is that most DVD movies are encoded with the MPEG2 codec at 8-bit color depth and a bitrate around 6000kbps. However, re-encoding the video at a precieved as visually lossless CRF value of 16 using the HEVC codec, the slow preset and 10-bit color depth will produce a file that is around 25% of the originals size. Thus, in most situations the re-encoded video will never hit the 2000kbps bitrate cap.

### Why scale all movies to 720p?
The Plex server will transcode all videos to be 720p when the Plex client is set up to limit bitrates to 4000kbps or less (and 480p when set up to limit bitrates to 1500kbps or less). So we never want a re-encoded source to have a resolution higher than 720p as the resulting video will always be blocky and bitrate starved because Plex servers transcode using the less visually efficient AVC codec and 8-bit color depth settings. Along these same lines, upscaling DVD videos to 720p during the re-encoding process lets us use advanced scaling and filtering algorithms that allow us to achieve a better visual result than if we tried to do scale the movie in real time.

### Why use 10-bit color depth?
When the source video has an 8-bit color depth re-encoding the video using a 10-bit color depth lets us achieve the same visual result for about 5% less bitrate. This lowers the chance that the re-encoding the video will hit the 2000kbps bitrate cap. Additionally, using the 10-bit color depth will prevent banding when the source material is 10-bit or the upscale algorithm and filters combine to produce a gradual gradient.

### Why use the HEVC codec?
The HEVC codec is about 40% more efficient than the AVC codec which allows us to re-encode DVD videos using a CRF value of 16 to produce a video that in most situations has a bitrate less than 2000kbps. Additioanlly, most consumer video decoders support the HEVC codec with a 10-bit color depth but only support the AVC codec with an 8-bit color depth. Thus, a Plex server is able to direct stream a 10-bit HEVC video to the Plex client but most transcode the 8-bit AVC video while streaming the video to the Plex client.

