const std = @import("std");
const IncludeTree = @import("dergdrive").client.track.IncludeTree;
const pipe_adapter = @import("pipe_adapter.zig");
const File = std.fs.File;
const RawFileChunkBuffer = @import("RawFileChunkBuffer.zig");

const FileReader = @This();

incl_tree: IncludeTree,
raw_file_adapter: *pipe_adapter.RawFilePipeAdapter,

const PipeFileError = File.GetEndPosError || std.Io.Reader.ShortError;

fn pipeFile(self: *FileReader, file: File) PipeFileError!void {
    var piped_size: usize = 0;
    const file_size = try file.getEndPos();
    var reader = file.reader(&.{});

    while (piped_size < file_size) {
        const chunk_buf: *RawFileChunkBuffer = self.raw_file_adapter.claimChunkBuf(.write);
        defer self.raw_file_adapter.unclaimChunkBuf(chunk_buf, .write);

        const write_buf = chunk_buf.chunk_buf.getBuf();

        const bytes_read = reader.interface.readSliceShort(write_buf) catch {
            // TODO handle specific error
            // possibly send a cancel upload request for this file, so that partial uploads do not occur
            return PipeFileError.ReadFailed;
        };

        {
            chunk_buf.chunk_buf.w_lock.lock();
            defer chunk_buf.chunk_buf.w_lock.unlock();

            chunk_buf.chunk_buf.data_len = bytes_read;
        }

        piped_size += bytes_read;
    }
}
