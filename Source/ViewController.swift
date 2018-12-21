import Cocoa
import MetalKit

var vc:ViewController! = nil
var g = Graphics()
var aData = ArcBallData()

class ViewController: NSViewController, NSWindowDelegate, WGDelegate {
    var control = Control()
    var cBuffer:MTLBuffer! = nil
    var coloringTexture:MTLTexture! = nil
    var outTextureL:MTLTexture! = nil
    var outTextureR:MTLTexture! = nil
    var pipeline1:MTLComputePipelineState! = nil
    let queue = DispatchQueue(label:"Q")
    
    var circleMove:Bool = false
    var isStereo:Bool = false
    var autoChg:Bool = false
    
    var threadGroupCount = MTLSize()
    var threadGroups = MTLSize()

    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    
    @IBOutlet var wg: WidgetGroup!
    @IBOutlet var metalTextureViewL: MetalTextureView!
    @IBOutlet var metalTextureViewR: MetalTextureView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        
        do {
            let defaultLibrary:MTLLibrary! = device.makeDefaultLibrary()
            guard let kf1 = defaultLibrary.makeFunction(name: "rayMarchShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
        } catch { fatalError("error creating pipelines") }
        
        let w = pipeline1.threadExecutionWidth
        let h = pipeline1.maxTotalThreadsPerThreadgroup / w
        threadGroupCount = MTLSizeMake(w, h, 1)

        control.style = 0
        control.lighting.ambient = 0.5
        control.lighting.diffuse = 0.5
        control.lighting.specular = 0.5
        control.lighting.harshness = 0.5
        control.lighting.saturation = 0.5
        control.lighting.gamma = 0.5
        control.multiplier = 0.5

        wg.delegate = self
        initializeWidgetGroup()
        layoutViews()
        
        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.timerHandler() }
    }
    
    override func viewDidAppear() {
        view.window?.delegate = self
        resizeIfNecessary()
        dvrCount = 1 // resize metalviews without delay
        reset()
    }
    
    //MARK: -
    
    func resizeIfNecessary() {
        let minWinSize:CGSize = CGSize(width:700, height:700)
        var r:CGRect = (view.window?.frame)!
        
        if r.size.width < minWinSize.width || r.size.height < minWinSize.height {
            r.size = minWinSize
            view.window?.setFrame(r, display: true)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        resizeIfNecessary()
        resetDelayedViewResizing()
    }
    
    //MARK: -
    
    var dvrCount:Int = 0
    
    // don't realloc metalTextures until they have finished resizing the window
    func resetDelayedViewResizing() {
        dvrCount = 10 // 20 = 1 second delay
    }
    
    //MARK: -

    var circleAngle:Float = 0
    var askToClearColoringParams:Bool = false

    @objc func timerHandler() {
        var refresh:Bool = wg.update()
        let chgAmount = cosf(circleAngle) / 100
        
        if askToClearColoringParams {
            askToClearColoringParams = false
            
            let alert = NSAlert()
            alert.messageText = "Zero the coloring parameters?"
            alert.informativeText = "Set coloring parameters to not affect texture colors?"
            alert.addButton(withTitle: "NO")
            alert.addButton(withTitle: "YES")
            alert.beginSheetModal(for: vc.view.window!) {( returnCode: NSApplication.ModalResponse) -> Void in
                if returnCode.rawValue == 1001 {
                    self.control.lighting.ambient = 0
                    self.control.lighting.diffuse = 0
                    self.control.lighting.specular = 0.7
                    self.control.lighting.harshness = 0
                    self.control.lighting.saturation = 0
                    self.control.lighting.gamma = 0
                    self.control.color = float3(1)
                    self.wg.refresh()
                    self.updateImage()
                }
            }
        }
        
        if autoChg {
            func alter(_ v: inout Float) {
                if (arc4random() & 1023) < 800 { return }
                v += chgAmount
                if v < 0 { v = 0 } else if v > 1 { v = 1 }
            }
            
            alter(&control.lighting.ambient)
            alter(&control.lighting.diffuse)
            alter(&control.lighting.specular)
            alter(&control.lighting.harshness)
            alter(&control.lighting.saturation)
            alter(&control.lighting.gamma)
            alter(&control.lighting.shadowMin)
            alter(&control.lighting.shadowMax)
            alter(&control.lighting.shadowMult)
            alter(&control.lighting.shadowAmt)
            
            circleAngle += 0.02
            wg.refresh()
            refresh = true
        }

        if refresh && !isBusy { updateImage() }
        
        if dvrCount > 0 {
            dvrCount -= 1
            if dvrCount <= 0 {
                layoutViews()
            }
        }
    }
    
    //MARK: -
    
    func initializeWidgetGroup() {
        wg.reset()
        wg.addSingleFloat("Z",&control.zoom,  0.2,2, 0.03, "Zoom")
        wg.addSingleFloat("D",&control.minDist, 0.0002,0.05,0.001, "minDist")
        wg.addSingleFloat("2",&control.multiplier,0.01,1,0.002, "Multiplier")
        wg.addSingleFloat("3",&control.dali,0.1,1,0.001, "Dali")
        wg.addLine()
        wg.addTriplet("L",&control.light,-10,10,0.3,"Light")
        wg.addTriplet("C",&control.color,0,1,0.02,"Tint")
        
        let sPmin:Float = 0.01
        let sPmax:Float = 1
        let sPchg:Float = 0.01
        wg.addColor(.autoChg,Float(RowHT * 11))
        wg.addSingleFloat("4",&control.lighting.ambient,sPmin,sPmax,sPchg, "ambient")
        wg.addSingleFloat("",&control.lighting.diffuse,sPmin,sPmax,sPchg, "diffuse")
        wg.addSingleFloat("",&control.lighting.specular,sPmin,sPmax,sPchg, "specular")
        wg.addSingleFloat("",&control.lighting.harshness,sPmin,sPmax,sPchg, "harsh")
        wg.addSingleFloat("",&control.lighting.saturation,sPmin,sPmax,sPchg, "saturate")
        wg.addSingleFloat("G",&control.lighting.gamma,sPmin,sPmax,sPchg, "gamma")
        wg.addSingleFloat("",&control.lighting.shadowMin,sPmin,sPmax,sPchg, "sMin")
        wg.addSingleFloat("",&control.lighting.shadowMax,sPmin,sPmax,sPchg, "sMax")
        wg.addSingleFloat("",&control.lighting.shadowMult,sPmin,sPmax,sPchg, "sMult")
        wg.addSingleFloat("",&control.lighting.shadowAmt,sPmin,sPmax,sPchg, "sAmt")
        wg.addCommand("5","auto Chg",.autoChg)
        
        wg.addLine()
        let str:String = control.style == 0 ? "Apollonian1" : "Apollonian2"
        wg.addCommand("S",str,.style)
        wg.addSingleFloat("6",&control.foam, 0.5,2,0.005, "Param1")
        wg.addSingleFloat("7",&control.foam2, 0.5,2,0.003, "Param2")
        
        if control.style == 0 {
            wg.addSingleFloat("8",&control.bend, 0.01,0.03,0.00002, "Param3")
        }
        
        wg.addLine()
        wg.addSingleFloat("F",&control.fog, 10,100,3, "Fog")
        wg.addLine()
        wg.addCommand("V","Save/Load",.saveLoad)
        wg.addCommand("H","Help",.help)
        wg.addCommand("N","Reset",.reset)
        
        wg.addLine()
        wg.addColor(.stereo,Float(RowHT * 2))
        wg.addCommand("O","Stereo",.stereo)
        let parallaxRange:Float = 0.008
        wg.addSingleFloat("P",&control.parallax, -parallaxRange,+parallaxRange,0.0002, "Parallax")
        
        wg.addLine()
        wg.addCommand("M","Move",.move)
        wg.addCommand("R","Rotate",.rotate)
        
        wg.addLine()
        wg.addColor(.texture,Float(RowHT - 2))
        wg.addCommand("9","Texture",.texture)
        wg.addTriplet("T",&control.txtCenter,0.01,1,0.002,"Pos, Sz")

        wg.refresh()
    }
    
    //MARK: -
    
    func wgCommand(_ cmd: WgIdent) {
        func presentPopover(_ name:String) {
            let mvc = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
            let vc = mvc.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(name)) as! NSViewController
            self.present(vc, asPopoverRelativeTo: wg.bounds, of: wg, preferredEdge: .maxX, behavior: .transient)
        }
        
        switch(cmd) {
        case .saveLoad :
            presentPopover("SaveLoadVC")
        case .help :
            presentPopover("HelpVC")
        case .reset :
            reset()
            updateImage()
        case .stereo :
            isStereo = !isStereo
            initializeWidgetGroup()
            layoutViews()
            updateImage()
        case .autoChg:
            autoChg = !autoChg
        case .texture :
            if control.txtOnOff > 0 {
                control.txtOnOff = 0
                updateImage()
            }
            else {
                loadImageFile()
            }
        case .refresh :
            updateImage()
        case .style :
            control.style = control.style > 0 ? 0 : 1
            wg.focus += 1   // hop to companion param1
            reset()
            initializeWidgetGroup()
            updateImage()
        default :
            break
        }
    }
    
    func wgGetColor(_ ident:WgIdent) -> NSColor {
        var shouldHighlight:Bool = false

        switch(ident) {
        case .autoChg : shouldHighlight = autoChg
        case .stereo  : shouldHighlight = isStereo
        case .texture : shouldHighlight = control.txtOnOff > 0
        default : break
        }
        
        return shouldHighlight ? NSColor(red:0.3, green:0.1, blue:0.1, alpha:1) : .black
    }
    
    func wgOptionSelected(_ ident: Int, _ index: Int) {}
    func wgGetString(_ ident: WgIdent) -> String { return "" }
    func wgToggle(_ ident: WgIdent) {}
    func wgOptionSelected(_ ident: WgIdent, _ index: Int) {}
    func wgGetOptionString(_ ident: WgIdent) -> String { return "" }
    
    //MARK: -
    
    func reset() {
        control.light = float3(1,1,1)
        control.color = float3(1,1,1)
        control.zoom = 0.956
        control.minDist = 0.006
//        control.lighting.ambient = 0.5
//        control.lighting.diffuse = 0.5
//        control.lighting.specular = 0.5
//        control.lighting.harshness = 0.5
//        control.lighting.saturation = 0.5
//        control.lighting.gamma = 0.5
//        control.multiplier = 0.5
        control.lighting.shadowMin = 0.5
        control.lighting.shadowMax = 0.5
        control.lighting.shadowMult = 0.5
        control.lighting.shadowAmt = 0.1
        control.dali = 1
        control.foam = 1.05265248
        control.foam2 = 1.06572711
        control.bend = 0.0202780124
        
        if control.style == 1 {
            control.minDist = 0.000464375014
            control.multiplier = 0.00999999977
            control.dali = 0.604027212
            control.foam = 0.5
            control.foam2 = 0.751381218
            control.bend = 0.0199999996
        }
        
        control.fog = 100
        autoChg = false
        arcBall.initialize(100,100)
        control.camera = float3(0.42461035, 10.847559, 2.5749633)
        control.focus = float3(0.42263266, 10.949086, 14.647235)
        
        initializeWidgetGroup()
        wg.hotKey("M")
    }
    
    //MARK: -
    
    func loadTexture(from image: NSImage) -> MTLTexture {
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!

        let textureLoader = MTKTextureLoader(device: device)
        do {
            let textureOut = try textureLoader.newTexture(cgImage:cgImage)

            control.txtSize.x = Float(cgImage.width)
            control.txtSize.y = Float(cgImage.height)
            control.txtCenter.x = 0.5
            control.txtCenter.y = 0.5
            control.txtCenter.z = 0.01

            askToClearColoringParams = true
            return textureOut
        }
        catch {
            fatalError("Can't load texture")
        }
    }

    func loadImageFile() {
        control.txtOnOff = 0

        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.title = "Select Image for Texture"
        openPanel.allowedFileTypes = ["jpg","png"]

        openPanel.beginSheetModal(for:self.view.window!) { (response) in
            if response.rawValue == NSApplication.ModalResponse.OK.rawValue {
                let selectedPath = openPanel.url!.path

                if let image:NSImage = NSImage(contentsOfFile: selectedPath) {
                    self.coloringTexture = self.loadTexture(from: image)
                    self.control.txtOnOff = 1
                }
            }

            openPanel.close()

            if self.control.txtOnOff > 0 { // just loaded a texture
                self.wg.moveFocus(1)  // companion texture widgets
                self.updateImage()
            }
        }
    }
    
    //MARK: -
    
    func layoutViews() {
        let xs = view.bounds.width
        let ys = view.bounds.height
        let xBase:CGFloat = wg.isHidden ? 0 : 125
        
        if !wg.isHidden {
            wg.frame = CGRect(x:0, y:0, width:xBase, height:ys)
        }
        
        if isStereo {
            metalTextureViewR.isHidden = false
            let xs2:CGFloat = (xs - xBase)/2
            metalTextureViewL.frame = CGRect(x:xBase, y:0, width:xs2, height:ys)
            metalTextureViewR.frame = CGRect(x:xBase+xs2+1, y:0, width:xs2, height:ys) // +1 = 1 pixel of bkground between
        }
        else {
            metalTextureViewR.isHidden = true
            metalTextureViewL.frame = CGRect(x:xBase, y:0, width:xs-xBase, height:ys)
        }
        
        setImageViewResolution()
        updateImage()
    }
    
    func controlJustLoaded() {
        wg.refresh()
        setImageViewResolution()
        updateImage()
    }
    
    func setImageViewResolution() {
        control.xSize = Int32(metalTextureViewL.frame.width)
        control.ySize = Int32(metalTextureViewL.frame.height)
        
        let xsz = Int(control.xSize)
        let ysz = Int(control.ySize)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: xsz,
            height: ysz,
            mipmapped: false)
        
        outTextureL = device.makeTexture(descriptor: textureDescriptor)!
        outTextureR = device.makeTexture(descriptor: textureDescriptor)!
        
        metalTextureViewL.initialize(outTextureL)
        metalTextureViewR.initialize(outTextureR)
        
        let xs = xsz/threadGroupCount.width + 1
        let ys = ysz/threadGroupCount.height + 1
        threadGroups = MTLSize(width:xs, height:ys, depth: 1)
    }
    
    //MARK: -
    
    func calcRayMarch(_ who:Int) {
        func toRectangular(_ sph:float3) -> float3 { let ss = sph.x * sin(sph.z); return float3( ss * cos(sph.y), ss * sin(sph.y), sph.x * cos(sph.z)) }
        func toSpherical(_ rec:float3) -> float3 { return float3(length(rec), atan2(rec.y,rec.x), atan2(sqrt(rec.x*rec.x+rec.y*rec.y), rec.z)) }
        
        var c = control
        
        if isStereo { if who == 0 { c.camera.x -= control.parallax } else { c.camera.x += control.parallax }}
        
        c.viewVector = c.focus - c.camera
        c.topVector = toSpherical(c.viewVector)
        c.topVector.z += 1.5708
        c.topVector = toRectangular(c.topVector)
        c.sideVector = cross(c.viewVector,c.topVector)
        c.sideVector = normalize(c.sideVector) * length(c.topVector)
        c.light = normalize(c.light)
        
        cBuffer.contents().copyMemory(from: &c, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(who == 0 ? outTextureL : outTextureR, index: 0)
        commandEncoder.setTexture(coloringTexture, index: 1)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    //MARK: -
    
    var isBusy:Bool = false
    
    func updateImage() {
        if isBusy { return }
        isBusy = true
        
        calcRayMarch(0)
        metalTextureViewL.display(metalTextureViewL.layer!)
        
        if isStereo {
            calcRayMarch(1)
            metalTextureViewR.display(metalTextureViewR.layer!)
        }
        
        isBusy = false
    }
    
    //MARK: -
    
    func alterAngle(_ dx:Float, _ dy:Float) {
        let center:CGFloat = 25
        arcBall.mouseDown(CGPoint(x: center, y: center))
        arcBall.mouseMove(CGPoint(x: center + CGFloat(dx), y: center + CGFloat(dy)))
        
        let direction = simd_make_float4(0,0.1,0,0)
        let rotatedDirection = simd_mul(aData.transformMatrix, direction)
        
        control.focus.x = rotatedDirection.x
        control.focus.y = rotatedDirection.y
        control.focus += control.camera
        
        updateImage()
    }
    
    func alterPosition(_ dx:Float, _ dy:Float, _ dz:Float) {
        func axisAlter(_ dir:float4, _ amt:Float) {
            let diff = simd_mul(aData.transformMatrix, dir) * amt / 300.0
            
            func alter(_ value: inout float3) {
                value.x -= diff.x
                value.y -= diff.y
                value.z -= diff.z
            }
            
            alter(&control.camera)
            alter(&control.focus)
        }
        
        let q:Float = optionKeyDown ? 50 : 5
        
        if shiftKeyDown {
            axisAlter(simd_make_float4(0,q,0,0),-dx * 2)
            axisAlter(simd_make_float4(0,0,q,0),dy)
        }
        else {
            axisAlter(simd_make_float4(q,0,0,0),dx)
            axisAlter(simd_make_float4(0,0,q,0),dy)
        }
        
        updateImage()
    }
    
    //MARK: -
    
    var shiftKeyDown:Bool = false
    var optionKeyDown:Bool = false
    var letterAKeyDown:Bool = false
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        
        updateModifierKeyFlags(event)
        
        switch event.keyCode {
        case 123:   // Left arrow
            wg.hopValue(-1,0)
            return
        case 124:   // Right arrow
            wg.hopValue(+1,0)
            return
        case 125:   // Down arrow
            wg.hopValue(0,-1)
            return
        case 126:   // Up arrow
            wg.hopValue(0,+1)
            return
        case 43 :   // '<'
            wg.moveFocus(-1)
            return
        case 47 :   // '>'
            wg.moveFocus(1)
            return
        case 53 :   // Esc
            NSApplication.shared.terminate(self)
        case 0 :    // A
            letterAKeyDown = true
        case 18 :   // 1
            wg.isHidden = !wg.isHidden
            layoutViews()
        default:
            break
        }
        
        let keyCode = event.charactersIgnoringModifiers!.uppercased()
        //print("KeyDown ",keyCode,event.keyCode)
        
        wg.hotKey(keyCode)
    }
    
    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        
        wg.stopChanges()
        
        switch event.keyCode {
        case 0 :    // A
            letterAKeyDown = false
        default:
            break
        }
        
    }
    
    //MARK: -
    
    func flippedYCoord(_ pt:NSPoint) -> NSPoint {
        var npt = pt
        npt.y = view.bounds.size.height - pt.y
        return npt
    }
    
    func updateModifierKeyFlags(_ ev:NSEvent) {
        let rv = ev.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        shiftKeyDown   = rv & (1 << 17) != 0
        optionKeyDown  = rv & (1 << 19) != 0
    }
    
    var pt = NSPoint()
    
    override func mouseDown(with event: NSEvent) {
        pt = flippedYCoord(event.locationInWindow)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateModifierKeyFlags(event)
        
        var npt = flippedYCoord(event.locationInWindow)
        npt.x -= pt.x
        npt.y -= pt.y
        wg.focusMovement(npt,1)
    }
    
    override func mouseUp(with event: NSEvent) {
        pt.x = 0
        pt.y = 0
        wg.focusMovement(pt,0)
    }
}

// ===============================================

class BaseNSView: NSView {
    override var acceptsFirstResponder: Bool { return true }
}
