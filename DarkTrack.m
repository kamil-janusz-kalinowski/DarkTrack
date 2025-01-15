function [outX,outY,outZ,EDOF,CR] = DarkTrack(holoSet,opts,adv)
% DarkTrack - algorithm that returns the 4D (space + time) location of 
% objects/particles present in input set of lensless digital in-line 
% holographic microscopy (DIHM) holograms (holoSet) and the extended depth 
% of focus (EDOF) reconstruction
%
% Inputs:
%   holoSet - 3D matrix containing a stack of holograms
%   
%   opts - struct that contains reconstruction options (system parameters)
%       opts.dist - propagation distance (mm) - a distance between camera
%           and the middle of object plane
%       opts.propRange - propagation range (um)
%           opts.propRange = [lower bound, upper bound]; (see drawing 
%               below). Can have negative values
%       opts.propStep - sampling in z direction (um)
%           propagationRange = opts.dist*1000+opts.propRange(1) : ...
%               opts.propStep : opts.dist*1000+opts.propRange(2)
%       ############## 
%       To properly set the opts.propRange and opts.propStep we recommend
%       to use the DarkFocus algorithm: https://github.com/MRogalski96/DarkFocus
%       ##############
%       opts.lambda - lightsource wavelength (um)
%       opts.pixSize - camera pixel size (um)
%       opts.mag - magnification of the lensless microscope setup
%       opts.n0 - background refractive index (default = 1)
%   
%   adv - struct that contains algorithm advanced options (optional)
%       adv.minPix - minimal number of pixels to classificate group of
%           pixels as object, not as background. Default - adv.minPix = 10
%       adv.showTmpRes - show algorithm results while algorithm is running
%           adv.showTmpRes = 0; - no
%           adv.showTmpRes = 1; - display in command window short info
%               after processing every 10th frame (default)
%           adv.showTmpRes = 2; - show EDOF image for each frame
%           adv.showTmpRes = 3; - show EDOF, CR and segmented 2D image
%       adv.NoF - number of frames that will be reconstructed (default -
%           adv.NoF = size(holoSet,3);) 
%       adv.backRemov - background removing method
%           adv.backRemov = 1; - hologram background is equal to the
%               average of all holograms
%               (default when the number of frames is >= 10)
%           adv.backRemov = 2; - hologram background is obtained through
%               gaussian filtering
%               (default when the number of frames is < 10)
%           adv.backRemov = 2D or 3D matrix; - adv.backRemov is set as
%               hologram background 
%       adv.useGPU - use GPU to accelerate the reconstruction
%           0 - No; 1 - Yes; 2 - auto (default) 
%
% Outputs:
%   outX(ON,FN), outY(ON,FN), outZ(ON,FN) - X, Y and Z positions of the
%       centers of reconstructed objects. If the ON object isn't present in
%       given FN frame, the cell will have NaN value.
%           ON - object number
%           FN - frame number
%   EDOF - extended depth of focus reconstruction - in each frame, each
%       object is movet to its focus plane. Object free region value is
%       equal 0
%   CR - classical darkfield recontruction - darkfield hologram propagated
%       to the propagationRange(end/2);
%
% Ilustrative drawing:
% dR(2) dR(1)   - here dR = opts.distRange; dR(1) < 0 and dR(2) > 0
% <---|<--|
%  _______
% |   |   |              |
% |object |              |
% |volume |              |detector
% |   |   |              |plane
% |___|___|              |
%      <-----------------|
%            opts.dist
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Created by:
%   Mikołaj Rogalski,
%   mikolaj.rogalski.dokt@pw.edu.pl
%   Institute of Micromechanics and Photonics,
%   Warsaw University of Technology, 02-525 Warsaw, Poland
%
% Last modified: 14.12.2021
% See the https://github.com/MRogalski96/DarkTrack for more info
% 
% Cite as:
% [1] Mikołaj Rogalski, Jose Angel Picazo-Bueno, Julianna Winnik, Piotr 
% Zdańkowski, Vicente Micó, Maciej Trusiak. "DarkTrack: a path across the 
% dark-field for holographic 4D particle tracking under Gabor regime." 
% 2021. Submitted
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    [opts, adv] = validateInputs(holoSet, opts, adv);
    
    [propRang, dPix, NoF, Sy, Sx, Sz, bckr_padded, FZ] = initVariables(holoSet, opts, adv);
    
    
    
    % x and y coordinates to remove the hologram padding
    yy1 = 101:(100+Sy);
    xx1 = 101:(100+Sx);
    
    t3 = size(adv.backRemov, 3);
    %% Loop through all frames
    for tt = 1:NoF
        %% Calculating the DarkVolume and GradVolume
        % Processed hologram
        if adv.useGPU == 1
            holo = gpuArray(double(holoSet(:,:,tt)));
        else
            holo = double(holoSet(:,:,tt));
        end
        % Pad array to avoid border errors
        holo_padded = padarray(holo,[100,100],0);
        
        % Calculating hologram background (for single frame)
        if t3 ~=1 || adv.backRemov == 2
            bckr_padded = createBackground(holo, adv);
        end
        
        [DarkVolume, GradVolume, CR(:,:,tt)] = calcDarkAndGradVolume(Sx, Sy, Sz, holo_padded, bckr_padded, propRang, FZ, xx1, yy1, adv, tt);
        
        if adv.showTmpRes == 3
            figure(51); imagesc(CR(:,:, tt)); colormap gray; axis image
            title(['Darkfield amplitude; frame = ',num2str(tt),'/',...
                num2str(NoF)]); pause(0.01)
        end
    
        %% Binarization and 2D segmentation
        
        img_bin = binarizeImageForSegmentation(DarkVolume, GradVolume, adv);
    
        % Segmentation
        [L,ON] = bwlabel(img_bin);
        
        if adv.showTmpRes == 3
            plotSegmentedObjects(L, ON, tt, NoF);
        end
        
        %% Calculating objects X,Y,Z position and extended depth of focus image 
        
        [EDOF(:,:,tt), X(:,tt), Y(:,tt), Z(:,tt)] = reconstructEDOFSingleFrame(GradVolume, DarkVolume, L, ON, Sy, Sx);
        showTmpRes(adv, EDOF(:,:,tt), tt, NoF)
    end
    
    %% final output processing
    
    X(X==0) = nan; Y(Y==0) = nan; Z(Z==0) = nan;
    [X_um, Y_um, Z_um] = convertPositionsToUm(X, Y, Z, dPix, opts);

    % 4D segmentation (to associate 
    if NoF > 1
        [outX,outY,outZ] = Segmentation4D(X_um,Y_um,Z_um);
    else
        outX = X_um;
        outY = Y_um;
        outZ = Z_um;
    end
end

%% Auxiliary functions
function uout = AS_propagate_optimized(FTu, z, FZ)
% Optimized version of Angular-Spectrum propagation method for fast 
% propagating same hologram multiple times at a different distances
% Inputs:
%   FTu - Fourier transform of the input hologram (without fftshift)
%   z - propagation distance (um)
%   FZ = sqrt(n0/lambda-fx^2-fy^2)
%       n0 - background refractive indext
%       lambda - light wavelength
%       fx and fy - hologram spatial frequencies along x and y axes

TF = exp(1i*2*pi*z*FZ);
% multiplication with the transfer function
FTu = FTu.*TF;
% inverse FT
uout = ifft2(FTu);
end

function [outX,outY,outZ] = Segmentation4D(X,Y,Z,frmeForg,dxL)
%Function that segments the objects XYZ locations in 4D
%
% Example:
%   X = [O1x, O1x, O2x, O3x, O2x          outX = [O1x, O1x, O1x, O1x, O1x
%        O2x, O3x, O1x, O2x, O1x    ->            O2x, O2x, O2x, O2x, O2x
%        O3x, O2x, O3x, O1x, O3x];                O3x, O3x, O3x, O3x, O3x];
% Where Onx is the x location of the n-th object. Each column consists the
% objects x locations in given frame (column 1 - frame 1 etc.)
%
% Inputs:
%   X,Y,Z - (x,y,z) locations of the objects.
%       Each column of the X,Y,Z represents objects locations in given frame.
%   frmeForg - when the object is not present in the next frameForg frames,
%       then the next objects positions will not be associated to it. 
%       (default frmeForg = 20)
%   dxL - Number of subsequent frames in which the object movement
%       direction is checked (default dxL = 5)
%   
% Outputs:
%   outX,outY,outZ - (x,y,z) locations of the segmented objects.
%       Each column of the X,Y,Z represents objects locations in given frame.
%       Each row represents one segmnted object
% 
% Created by
%   Mikołaj Rogalski,
%   mikolaj.rogalski.dokt@pw.edu.pl
%   Institute of Micromechanics and Photonics,
%   Warsaw University of Technology, 02-525 Warsaw, Poland
%
% Last modified: 26.10.2021

if nargin < 4; frmeForg = 20; end
if nargin < 5; dxL = 5; end
if isempty(frmeForg); frmeForg = 20; end
if isempty(dxL); dxL = 5; end

outX = X(:,1); outY = Y(:,1); outZ = Z(:,1);

% Number of frames
NoF = size(X,2);
% Number of objects in first frame
NoO = sum(~isnan(X(:,1)));

% Calculating the distances between objects X,Y positions in
% first 2 frames
tmpX = nonzeros(X(:,2)); tmpY = nonzeros(Y(:,2));
for qq = 1:NoO
    tmpDists = sqrt((X(qq,1)-tmpX).^2+(Y(qq,1)-tmpY).^2);
    tmpD(qq) = min(tmpDists);
end
maxDist = 10*prctile(tmpD,50);


for tt = 2:NoF
    
    minFrme = tt-frmeForg;
    if minFrme <1; minFrme = 1; end
    
    % Previous objects X,Y,Z locations
    X0 = nan(size(outX,1),1); Y0 = X0; Z0 = X0;
    X01 = X0; Y01 = Y0; Z01 = Z0;
    for ss = minFrme:tt-1
        tmpX0 = outX(:,ss); tmpY0 = outY(:,ss); tmpZ0 = outZ(:,ss);
        if ss>1; X01 = X0; Y01 = Y0; Z01 = Z0; end
        X0(~isnan(tmpX0)) = tmpX0(~isnan(tmpX0));
        Y0(~isnan(tmpY0)) = tmpY0(~isnan(tmpY0));
        Z0(~isnan(tmpZ0)) = tmpZ0(~isnan(tmpZ0));
    end
    dxt(:,mod(tt,dxL)+1) = X0-X01; dyt(:,mod(tt,dxL)+1) = Y0-Y01;
    dzt(:,mod(tt,dxL)+1) = Z0-Z01;
    for ff = 1:size(outX,1)
        tmpX = dxt(ff,:); tmpY = dyt(ff,:); tmpZ = dzt(ff,:);
        DX(ff) = mean(nonzeros(tmpX(~isnan(tmpX))));
        DY(ff) = mean(nonzeros(tmpY(~isnan(tmpY))));
        DZ(ff) = mean(nonzeros(tmpZ(~isnan(tmpZ))));
    end
    
    % Current objects X,Y,Z locations
    X1 = X(:,tt); X1 = X1(~isnan(X1));
    Y1 = Y(:,tt); Y1 = Y1(~isnan(Y1));
    Z1 = Z(:,tt); Z1 = Z1(~isnan(Z1));
    M1 = zeros(size(outX(:,tt-1)));
    for ii = 1:length(X1)
        if ~isnan(X1(ii))
            % distances (X,Y) between ii-th current object and all
            % previous objects
            distancesXY = sqrt((X0-X1(ii)).^2+(Y0-Y1(ii)).^2);
            
            % how many previous objects may be the current one:
            possibleXY = nonzeros(distancesXY<maxDist);
            sD = sum(possibleXY);
            if sD == 1 || tt == 2
                % there is only one object possible
                [~,loc] = min(distancesXY);
                outX(loc,tt) = X1(ii);
                outY(loc,tt) = Y1(ii);
                outZ(loc,tt) = Z1(ii);
                M1(loc) = M1(loc)+1;
            elseif sD == 0
                % object ii was not present in previous frames
                outX(end+1,tt) = X1(ii);
                outY(end+1,tt) = Y1(ii);
                outZ(end+1,tt) = Z1(ii);
                outX(end,1:tt-1) = nan;
                outY(end,1:tt-1) = nan;
                outZ(end,1:tt-1) = nan;
                dxt(end+1,:) = nan; dyt(end+1,:) = nan; dzt(end+1,:) = nan;
                M1(end+1) = 1;
            elseif sD > 1 && tt~=2
                % there are several objects that may by an
                % ii-th object
                vv = find((distancesXY < maxDist) == 1);
                dx0 = DX(ii);
                dy0 = DY(ii);
                dz0 = DZ(ii);
                dx = []; dy = []; dz = [];
                for qq = 1:length(vv)
                    dx(vv(qq)) = X1(ii) - X0(vv(qq));
                    dy(vv(qq)) = Y1(ii) - Y0(vv(qq));
                    dz(vv(qq)) = Z1(ii) - Z0(vv(qq));
                end
                dd = sqrt((dx0-dx).^2+(dy0-dy).^2+(dz0-dz).^2);
                [~,loc] = min(dd(vv));
                outX(vv(loc),tt) = X1(ii);
                outY(vv(loc),tt) = Y1(ii);
                outZ(vv(loc),tt) = Z1(ii);
                M1(vv(loc)) = M1(vv(loc))+1;
            end
            
        end
    end
    vv = find(M1==0);
    if ~isempty(vv)
        for pp = vv
            outX(pp,tt) = nan;
            outY(pp,tt) = nan;
            outZ(pp,tt) = nan;
        end
    end
    
    vv2 = find(M1>1);
    if ~isempty(vv2)
        for ss = 1:length(vv2)
            % Recalculate the outXYZ locations for which there were
            % assigned 2 X,Y,Z locations
            pp = vv2(ss);
            if ~isnan(X0(pp))
                % distances (X,Y) between ii-th current object and all
                % previous objects
                distancesXY = sqrt((X0(pp)-X1).^2+(Y0(pp)-Y1).^2);
                
                % how many previous objects may be the current one:
                possibleXY = nonzeros(distancesXY<maxDist);
                sD = sum(possibleXY);
                if sD == 1 || tt == 2
                    % there is only one object possible
                    [~,loc] = min(distancesXY);
                    outX(pp,tt) = X1(loc);
                    outY(pp,tt) = Y1(loc);
                    outZ(pp,tt) = Z1(loc);
                elseif sD > 1 && tt~=2
                    % there are several objects that may by an
                    % ii-th object
                    vv = find((distancesXY < maxDist) == 1);
                    dx0 = DX(pp);
                    dy0 = DY(pp);
                    dz0 = DZ(pp);
                    dx = []; dy = []; dz = [];
                    for qq = 1:length(vv)
                        dx(vv(qq)) = X1(vv(qq)) - X0(pp);
                        dy(vv(qq)) = Y1(vv(qq)) - Y0(pp);
                        dz(vv(qq)) = Z1(vv(qq)) - Z0(pp);
                    end
                    dd = sqrt((dx0-dx).^2+(dy0-dy).^2+(dz0-dz).^2);
                    [~,loc] = min(dd(vv));
                    outX(pp,tt) = X1(vv(loc));
                    outY(pp,tt) = Y1(vv(loc));
                    outZ(pp,tt) = Z1(vv(loc));
                end
            end
        end
    end
end
end

function [opts, adv] = validateInputs(holoSet, opts, adv)
    if nargin < 2
        error('Not enough input arguments ("holoSet" and/or "opts")');
    end

    % Validate required fields in opts
    requiredFields = {'dist', 'propRange', 'propStep', 'lambda', 'pixSize', 'mag'};
    missingFields = requiredFields(~isfield(opts, requiredFields));
    
    if ~isempty(missingFields)
        error(['Not enough opts parameters. Missing: ', strjoin(missingFields, ', ')]);
    end

    % Set default value for opts.n0 if not provided
    if ~isfield(opts, 'n0')
        opts.n0 = 1;
    end

    % Set defaults for adv if not provided
    if nargin < 3
        adv = struct();
    end

    advDefaults = struct('minPix', 10, 'showTmpRes', 1, 'NoF', size(holoSet, 3), 'useGPU', 2);

    fields = fieldnames(advDefaults);
    for i = 1:numel(fields)
        if ~isfield(adv, fields{i})
            adv.(fields{i}) = advDefaults.(fields{i});
        end
    end

    % Set default for backRemov
    if ~isfield(adv, 'backRemov')
        if size(holoSet, 3) < 10
            adv.backRemov = 2;
        else
            adv.backRemov = 1;
        end
    end

    % Check GPU usage
    if adv.useGPU == 2
        try
            tmpF = gpuDevice;
            adv.useGPU = 1;
        catch
            adv.useGPU = 0;
        end
    end
end

function [propRang, dPix, NoF, Sy, Sx, Sz, bckr_padded, FZ] = initVariables(holoSet, opts, adv)
    % Initialize required variables
    propRang = opts.dist*1000 + opts.propRange(1):opts.propStep:opts.dist*1000 + opts.propRange(2);
    dPix = opts.pixSize / opts.mag;
    NoF = adv.NoF;

    % Dimensions of hologram set
    [Sy, Sx, ~] = size(holoSet);
    Sz = length(propRang);
    
    % Background processing (padding, etc.)
    bckr_padded = processBackground(holoSet, adv, Sy, Sx);

    FZ = calcFZ(Sx, Sy, dPix, opts, adv);
end

function bckr_padded = processBackground(holoSet, adv, Sy, Sx)
    % Calculating hologram background - for all frames
    [t1,t2,t3] = size(adv.backRemov);
    if t3 == 1 % adv.backRemov = single value or 2D array
        if t1 == 1 && t2 == 1  % adv.backRemov = single value
            if adv.backRemov == 1   % background = mean image from all frames
                bckr = mean(holoSet,3);
                % Pad array to avoid border errors
                bckr_padded = padarray(bckr,[100,100],0);
            end
        elseif t1 == Sy && t2 == Sx % background for all holograms = adv.backRemov 
            bckr = adv.backRemov;
            % Pad array to avoid border errors
            bckr_padded = padarray(bckr,[100,100],0);
        else
            error('Wrong adv.backRemov dimensionality (should be equal to holoSet)')
        end
    end
end

function FZ = calcFZ(Sx, Sy, dPix, opts, adv)
    % Precomputing the FZ parameter for angular spectrum method (to not compute
    % this multiple times inside the algorithm loop)
    Ny = Sy + 200; % Size of padded hologram
    Nx = Sx + 200;
    dfx = 1/Nx/dPix; % Sampling in x and y
    dfy = 1/Ny/dPix;
    fx=(-Nx/2:Nx/2-1)*dfx;
    fy=(-Ny/2:Ny/2-1)*dfy;
    [FX,FY] = meshgrid(fx,fy); % Spatial frequencies along x and y
    FX = fftshift(FX); FY = fftshift(FY);
    if adv.useGPU == 1
        FZ = gpuArray(sqrt((opts.n0/opts.lambda).^2-FX.^2-FY.^2));
    else
        FZ = sqrt((opts.n0/opts.lambda).^2-FX.^2-FY.^2);
    end
    FZ(~isreal(FZ))=0;
end

function bckr_padded = createBackground(holo, adv)
    if adv.backRemov == 2   % Calculate background with gaussian filtering
        bckr = imgaussfilt(holo,30);
    elseif t1 == Sy && t2 == Sx % This hologram background = adv.backRemov(:,:,tt)
        bckr = adv.backRemov(:,:,tt);
    else
        error('Wrong adv.backRemov dimensionality (should be equal to holoSet)')
    end
    % Pad array to avoid border errors
    bckr_padded = padarray(bckr,[100,100],0);
end

function [DarkVolume, GradVolume, CR] = calcDarkAndGradVolume(Sx, Sy, Sz, holo_padded, bckr_padded, propRang, FZ, xx1, yy1, adv, tt)
    DarkVolume = zeros(Sy,Sx,Sz);
    GradVolume = zeros(Sy,Sx,Sz);
    % Darkfield hologram
    holo_dark = holo_padded - bckr_padded;
    FTholo_dark = fft2(holo_dark);
    
    % Creating DarkVolume and GradVolume
    for mm = 1:Sz
        % Propagate the darkfield hologram at propRang(mm) distance
        Obj = AS_propagate_optimized(FTholo_dark,propRang(mm),FZ);
        amp = abs(Obj(yy1,xx1));
        
        % Compute CR
        if mm == round(Sz/2)
            CR = amp;
        end
        
        if adv.useGPU == 1
            DarkVolume(:,:,mm) = gather(amp);
            [gx, gy] = gradient(amp);
            GradVolume(:,:,mm) = gather(gx.^2 + gy.^2);
        else
            DarkVolume(:,:,mm) = amp;
            [gx, gy] = gradient(amp);
            GradVolume(:,:,mm) = gx.^2 + gy.^2;
        end

        if adv.showTmpRes == 3
            figure(51); imagesc(amp); colormap gray; axis image
            title(['Darkfield amplitude; frame = ',num2str(tt),'/',...
                num2str(NoF)]); pause(0.01)
        end
    end
end

function plotSegmentedObjects(L, ON, tt, NoF)
    % Function to display the segmented objects with a customized colormap
    %
    % Inputs:
    %   L   - The segmented objects 2D matrix
    %   ON  - The number of segments (used for the jet colormap)
    %   tt  - The current frame number
    %   NoF - The total number of frames
    
    cmap = [1, 1, 1; jet(ON)];  % Create a colormap with white for background and jet for segments
    figure(52); 
    imagesc(L); 
    colormap(cmap); 
    axis image;
    title(['Segmented objects 2D; frame = ', num2str(tt), '/', num2str(NoF)]);
    pause(0.01);  % Pause for 0.01 seconds
end

function img_bin = binarizeImageForSegmentation(DarkVolume, GradVolume, adv)
    % Binarized image
    TB = max(DarkVolume,[],3).*imgaussfilt(max(GradVolume,[],3),4);
    % Normalizing 0-1
    im = TB; im = im - min(im(:)); im = im./max(im(:));
    % Binarization thresholds
    T1 = adaptthresh(im);
    T2 = graythresh(im);
    % Binarizing
    img_bin = imbinarize(im,(T1+T2)/2);    
    % Removing small objects
    img_bin = bwareaopen(img_bin,adv.minPix);
end

function showTmpRes(adv, frme2D, tt, NoF)
    % Function to display extended depth of focus reconstruction or print progress
    %
    % Inputs:
    %   adv    - A structure containing the 'showTmpRes' field
    %   frme2D - The 2D frame to display for extended depth of focus reconstruction
    %   tt     - The current frame number
    %   NoF    - The total number of frames
    
    if adv.showTmpRes > 1
        % Display the extended depth of focus reconstruction
        figure(53); 
        imagesc(frme2D); 
        colormap gray; 
        axis image;
        title(['Extended depth of focus reconstruction; frame = ', num2str(tt), '/', num2str(NoF)]);
        pause(0.01);
    elseif adv.showTmpRes == 1
        % Print progress every 10th frame
        if mod(tt, 10) == 0
            disp(['DarkTrack; Processed ', num2str(tt), '/', num2str(NoF), ' images']);
        end
    end
end

function [EDOF, X, Y, Z] = reconstructEDOFSingleFrame(GradVolume, DarkVolume, L, ON, Sy, Sx)
    % Function to reconstruct frame with extended depth of focus (EDOF) for a single frame
    %
    % Inputs:
    %   GradVolume - Gradient volume with maximum values across the z-axis
    %   DarkVolume - Volume with dark object intensity values
    %   L          - Label matrix (objects in the 2D image)
    %   ON         - Total number of objects
    %   Sy         - Height of the image (number of rows)
    %   Sx         - Width of the image (number of columns)
    %
    % Outputs:
    %   EDOF      - Reconstructed extended depth of focus frame
    %   X         - X locations of the objects
    %   Y         - Y locations of the objects
    %   Z         - Z locations of the objects
    
    % Initialize the reconstructed frame with EDOF
    EDOF = zeros(Sy, Sx);
    
    % GradVolume maxima maps and their locations in the z direction
    [mks, locs] = max(GradVolume, [], 3);
    
    % Initialize vectors for storing object locations
    X = zeros(ON, 1); % X locations of the objects
    Y = zeros(ON, 1); % Y locations of the objects
    Z = zeros(ON, 1); % Z locations of the objects
    
    % Loop through all objects in the 2D image
    for ff = 1:ON
        % Mask the object
        mask = zeros(size(L));
        mask(L == ff) = 1;
        
        % Take only the 20% of highest mks values (and corresponding locs)
        v1 = mks(mask ~= 0);
        v2 = locs(mask ~= 0);
        q = prctile(v1, 80);
        v1T = v1(v1 > q);
        v2T = v2(v1 > q);
        
        % Z location of this object
        z = sum(v1T .* v2T) / sum(v1T);
        
        % (x, y) location of this object
        m = max(max(DarkVolume(:,:,round(z)) .* mask));
        [y, x] = find(DarkVolume(:,:,round(z)) .* mask == m, 1);
        
        % Store object locations
        X(ff) = x; 
        Y(ff) = y; 
        Z(ff) = z(1);
        
        % Add this object to the EDOF image
        tmp = mask .* DarkVolume(:,:,round(z));
        EDOF(mask == 1) = tmp(mask == 1);
    end
end

function [X_um, Y_um, Z_um] = convertPositionsToUm(X, Y, Z, dPix, opts)
    % convert X,Y,Z to um
    X_um = X*dPix;
    Y_um = Y*dPix;
    Z_um = (Z-1)*opts.propStep + opts.propRange(1);
end

