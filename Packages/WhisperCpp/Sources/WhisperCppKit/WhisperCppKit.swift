import Foundation
import CWhisper

/// whisper.cpp 封装入口（服务实现在 WhisperTranscriptionService）
public enum WhisperCppKit {
    /// whisper.cpp 运行时版本
    public static var runtimeVersion: String {
        String(cString: whisper_version())
    }

    /// 系统信息（含 Metal/Accelerate 能力）
    public static var systemInfo: String {
        String(cString: whisper_print_system_info())
    }
}
