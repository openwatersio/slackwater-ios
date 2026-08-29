// Slackwater — GPL v3. The JSCore fitter: chs-bundle.js + chs-glue.js run in
// JavaScriptCore to turn decimated samples into harmonic constituents.
//
// Constraints this bridge is built to:
//   - JSContext.exceptionHandler is set (JS errors are silent without it)
//   - nothing fetches inside JSCore — samples cross as JSON strings on an
//     epoch-ms bridge, fetched on the Swift side
//   - BASIS + SA/SSA constituent list (in chs-glue.js)
import Foundation
import JavaScriptCore

struct ChsFitResult: Decodable {
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
}

/// Runs chs-bundle.js + chs-glue.js in JavaScriptCore, off the main thread.
/// One context, reused across stations within a fit run.
final class ChsFitter {
    private var context: JSContext?
    private var jsError: String?

    private func makeContext() throws -> JSContext {
        if let context { return context }
        let ctx = JSContext()!
        ctx.exceptionHandler = { [weak self] _, exc in self?.jsError = exc?.toString() }
        // JSCore has no console; shim it so a stray log can't crash the fit.
        ctx.evaluateScript("var console = {log:function(){},warn:function(){},error:function(){},info:function(){},debug:function(){}};")
        for name in ["chs-bundle", "chs-glue"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js") else {
                throw ChsError.failed("\(name).js missing from bundle")
            }
            ctx.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            if let e = jsError { throw ChsError.failed("\(name).js: \(e)") }
        }
        context = ctx
        return ctx
    }

    func fit(samples: [ChsSample]) async throws -> ChsFitResult {
        let json = String(data: try JSONEncoder().encode(samples), encoding: .utf8)!
        let ctx = try makeContext()
        jsError = nil
        guard let out = ctx.objectForKeyedSubscript("fitTides")?.call(withArguments: [json]),
              jsError == nil, let str = out.toString() else {
            throw ChsError.failed(jsError ?? "fitTides returned nothing")
        }
        return try JSONDecoder().decode(ChsFitResult.self, from: Data(str.utf8))
    }
}
