#import "LegacyDistanceInteractionAdapter.h"

#import "MeasurementDomain.h"
#import "MeasurementInteraction.h"

@implementation LegacyDistanceInteractionAdapter

+ (MeasurementInteractionDefinition *)interactionDefinition
{
    static MeasurementInteractionDefinition *definition;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        MeasurementOverlaySegment *segment = [MeasurementOverlaySegment
            segmentFrom:MedisaleLandmarkIdentifierEndpointA
                     to:MedisaleLandmarkIdentifierEndpointB
                  error:&error];
        definition = [MeasurementInteractionDefinition
            definitionWithStableIdentifier:@"legacy-distance-interaction-v1"
            method:[MeasurementMethodDefinition legacyImageDistanceV1]
            collectionOrder:@[@(MedisaleLandmarkIdentifierEndpointA),
                              @(MedisaleLandmarkIdentifierEndpointB)]
            overlaySegments:segment == nil ? @[] : @[segment]
            error:&error];
        NSCAssert(definition != nil, @"The legacy interaction must be valid.");
    });
    return definition;
}

@end
