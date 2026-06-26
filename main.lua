local dimensions = Style.GetParameterValues().Dimensions
local dColl = tostring(dimensions.CollectorDiameter)
local dOut = tostring(dimensions.OutletsDiameter)
local distEdg = dimensions.DistanceEdge
local distOut = dimensions.DistanceOutput
local exec = tonumber(Style.GetParameterValues().Execution.Stock) 
local valveExsec =tostring(Style.GetParameterValues().Execution.Valves)

local dimTable = {
    D0_50={d=12.7,m=9,e=24,tSize=PipeThreadSize.D0_50},
    D0_75={d=19.05,m=9,e=31,tSize=PipeThreadSize.D0_75},
    D1_0={d=25.4,m=10,e=37,tSize=PipeThreadSize.D1_0},
    D1_25={d=31.75,m=11,e=43,tSize=PipeThreadSize.D1_25},
    D1_50={d=38.1,m=12,e=49,tSize=PipeThreadSize.D1_50}
}

local dimColl = dimTable[dColl]
local dimOut = dimTable[dOut]
local n=5
local l=distEdg*2+distOut*(n-1)
local inConnPlac = Placement3D(Point3D(-l/2,0,0),Vector3D(-1,0,0),Vector3D(0,1,0))
local outConnPlac = Placement3D(Point3D(l/2-dimColl.m,0,0),Vector3D(1,0,0),Vector3D(-1,0,0))
local outY = dimColl.d*0.5/math.sin(math.pi/4)-(dimColl.d*0.5+3)
local outPlac = Placement3D(Point3D(-l/2+distEdg,-outY,-(dimOut.m+dimColl.d/2+3)),Vector3D(0,0,-1),Vector3D(1,0,0))
local valveRotateAxis = Axis3D(Point3D(-l/2+distEdg,-outY,-dimColl.d/2-3),Vector3D(1,0,0))
local valvePlac = Placement3D(Point3D(-l/2+distEdg,-outY,dimColl.d/2+1),Vector3D(0,0,1),Vector3D(1,0,0))
valvePlac:Rotate(valveRotateAxis,math.pi/4*exec)

function circle(d)
    return CreateCircle2D(Point2D(0,0),d/2)
end

function polygon(d,n)
    local point = Point2D(0,d/2)
    local points = {}
    for i=0,n do
        table.insert(points, point:Clone():Rotate(Point2D(0,0),2*math.pi/n*i))
    end
    return CreatePolyline2D(points)
end

function nutPipe(plac,dimTab)
    return Subtract(
        Extrude(polygon(dimTab.e,8),ExtrusionParameters(dimTab.m),plac),
        Extrude(circle(dimColl.d-2),ExtrusionParameters(dimTab.m),plac))
end

function collector()
    return Unite({
        Extrude(circle(dimColl.d-2),ExtrusionParameters(0,dimColl.m),inConnPlac),
        Extrude(circle(dimColl.d),ExtrusionParameters(0,l-dimColl.m*2),inConnPlac)
        :Shift(dimColl.m,0,0),
        nutPipe(outConnPlac,dimColl)
    })
end

function tuningValve()
    return Unite(
        Extrude(polygon(20,10),ExtrusionParameters(7)),
        Extrude(circle(15),ExtrusionParameters(4)):Shift(0,0,7))   
end

function flowMeterValve()
    return Unite({
        tuningValve(),
        Extrude(circle(6),ExtrusionParameters(12)):Shift(0,0,11),
        CreateSphere(3):Shift(0,0,23)
    })   
end

function termostaticValve()
    local plac = Placement3D(Point3D(0,0,0),Vector3D(0,0,1),Vector3D(1,0,0))
    return Unite({
        Extrude(circle(22),ExtrusionParameters(20)),
        Extrude(polygon(22,12),ExtrusionParameters(5))
        :Shift(0,0,20)
    })
    --[[Loft(
        {circle(20),polygon(23,12)},
        {plac,plac:Clone():Shift(0,0,25)}
    ) ]]
end

local valves = {
        V0 = Extrude(polygon(dimOut.d-3,8),ExtrusionParameters(1)),
        V1 = tuningValve(),
        V2 = flowMeterValve(),
        V3 = termostaticValve()
}

function pipeOutlet(plac,valvePlac)
    local plac1 = plac:Clone():Shift(0,0,dimOut.m+3)
    return Unite({
        Extrude(circle(dimOut.d),ExtrusionParameters(0,dimOut.m),plac),
        Extrude(circle(dimOut.d-2),ExtrusionParameters(3),plac1),
        Loft({circle(dimOut.d-2),circle(dimOut.d-2)},{plac1,valvePlac}),
        valves[valveExsec]:Clone():Transform(valvePlac:GetMatrix())
    })
end

function pipeOutlets()
    local pipe = pipeOutlet(outPlac,valvePlac)
    for i=1,n-1 do
        pipe =Unite(pipe,
        pipeOutlet(outPlac:Clone():Shift(distOut*i,0,0),valvePlac:Clone():Shift(distOut*i,0,0)))
    end
    return pipe
end

local solid = Unite({collector(),
pipeOutlets()
})

Style.SetDetailedGeometry(ModelGeometry():AddSolid(solid))

function collPorts(dimTab,collPort,plac)
    local port = Style.GetPort(collPort)
    port:SetPlacement(plac)
    port:SetPipeParameters(PipeConnectorType.Thread,dimTab.tSize)
end

collPorts(dimColl,"CollectorInlet",inConnPlac)
collPorts(dimColl,"CollectorOutlet",outConnPlac)

for i=0,n-1 do
    local outPort = "Outlet"..i+1
    collPorts(dimOut,outPort,outPlac:Clone():Shift(distOut*i,0,0))
end

local symbolicSet = GeometrySet2D()
local symbolicCollector = CreateLineSegment2D(
    Point2D(inConnPlac:GetOrigin():GetX(),0),
    Point2D(outConnPlac:GetOrigin():GetX(),0))
symbolicSet:AddCurve(symbolicCollector)

local outLine = CreateLineSegment2D(Point2D(outPlac:GetOrigin():GetX(),0),
    Point2D(outPlac:GetOrigin():GetX(),outPlac:GetOrigin():GetZ()))

symbolicSet:AddCurve(outLine)
for i=0,n-1 do
    symbolicSet:AddCurve(outLine:Clone():Shift(distOut*i,0))
end

local symbolicPlac = Placement3D(Point3D(0,0,0),Vector3D(0,-1,0),Vector3D(1,0,0))
local symbolic = ModelGeometry():AddGeometrySet2D(symbolicSet,symbolicPlac)
Style.SetSymbolicGeometry(symbolic)
